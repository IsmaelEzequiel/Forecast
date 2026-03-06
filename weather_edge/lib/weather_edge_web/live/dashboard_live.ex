defmodule WeatherEdgeWeb.DashboardLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.Stations
  alias WeatherEdge.Markets
  alias WeatherEdge.Trading.Position
  alias WeatherEdge.PubSubHelper

  import Ecto.Query
  import WeatherEdgeWeb.Components.HeaderComponent
  import WeatherEdgeWeb.Components.AddStationModalComponent
  import WeatherEdgeWeb.Components.StationCardComponent

  @impl true
  def mount(_params, _session, socket) do
    stations = Stations.list_stations()

    clusters_by_station =
      Enum.into(stations, %{}, fn station ->
        {station.code, Markets.active_clusters_for_station(station.code)}
      end)

    positions =
      Position
      |> where([p], p.status == "open")
      |> WeatherEdge.Repo.all()

    positions_by_cluster =
      Enum.into(positions, %{}, fn p -> {p.market_cluster_id, p} end)

    if connected?(socket) do
      subscribe_to_topics(stations)
    end

    wallet_address = Application.get_env(:weather_edge, :polymarket)[:wallet_address]

    {:ok,
     assign(socket,
       stations: stations,
       clusters_by_station: clusters_by_station,
       positions: positions,
       positions_by_cluster: positions_by_cluster,
       signals: [],
       balance: nil,
       wallet_address: wallet_address,
       show_add_station_modal: false,
       modal_step: :input,
       modal_code: "",
       modal_loading: false,
       modal_error: nil,
       modal_station_info: nil
     )}
  end

  @impl true
  def handle_info({:station_created, station}, socket) do
    stations = [station | socket.assigns.stations] |> Enum.sort_by(& &1.code)
    clusters = Markets.active_clusters_for_station(station.code)
    clusters_by_station = Map.put(socket.assigns.clusters_by_station, station.code, clusters)

    subscribe_station(station)

    {:noreply, assign(socket, stations: stations, clusters_by_station: clusters_by_station)}
  end

  def handle_info({:station_updated, station}, socket) do
    stations =
      Enum.map(socket.assigns.stations, fn s ->
        if s.code == station.code, do: station, else: s
      end)

    {:noreply, assign(socket, stations: stations)}
  end

  def handle_info({:station_deleted, station}, socket) do
    stations = Enum.reject(socket.assigns.stations, &(&1.code == station.code))
    clusters_by_station = Map.delete(socket.assigns.clusters_by_station, station.code)
    {:noreply, assign(socket, stations: stations, clusters_by_station: clusters_by_station)}
  end

  def handle_info({:balance_updated, balance}, socket) do
    {:noreply, assign(socket, balance: balance)}
  end

  def handle_info({:position_updated, position}, socket) do
    positions =
      Enum.map(socket.assigns.positions, fn p ->
        if p.id == position.id, do: position, else: p
      end)

    positions_by_cluster = Map.put(socket.assigns.positions_by_cluster, position.market_cluster_id, position)

    {:noreply, assign(socket, positions: positions, positions_by_cluster: positions_by_cluster)}
  end

  def handle_info({:forecast_updated, _station_code}, socket) do
    {:noreply, socket}
  end

  def handle_info({:new_event, _station_code, _cluster}, socket) do
    stations = socket.assigns.stations

    clusters_by_station =
      Enum.into(stations, %{}, fn station ->
        {station.code, Markets.active_clusters_for_station(station.code)}
      end)

    {:noreply, assign(socket, clusters_by_station: clusters_by_station)}
  end

  def handle_info({:do_validate_station, code}, socket) do
    alias WeatherEdge.Forecasts.MetarClient

    case MetarClient.validate_station(code) do
      {:ok, info} ->
        {:noreply,
         assign(socket,
           modal_loading: false,
           modal_step: :confirm,
           modal_station_info: info
         )}

      {:error, :invalid_station} ->
        {:noreply,
         assign(socket,
           modal_loading: false,
           modal_error: "Invalid ICAO code"
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           modal_loading: false,
           modal_error: "Could not validate station. Please try again."
         )}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_add_station_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_add_station_modal: true,
       modal_step: :input,
       modal_code: "",
       modal_loading: false,
       modal_error: nil,
       modal_station_info: nil
     )}
  end

  def handle_event("close_add_station_modal", _params, socket) do
    {:noreply, assign(socket, show_add_station_modal: false)}
  end

  def handle_event("validate_station", %{"code" => code}, socket) do
    code = String.upcase(String.trim(code))

    if String.length(code) < 3 do
      {:noreply, assign(socket, modal_error: "Please enter a valid ICAO code (3-4 characters)")}
    else
      send(self(), {:do_validate_station, code})
      {:noreply, assign(socket, modal_loading: true, modal_error: nil, modal_code: code)}
    end
  end

  def handle_event("confirm_add_station", _params, socket) do
    case Stations.create_station(%{code: socket.assigns.modal_code}) do
      {:ok, _station} ->
        {:noreply, assign(socket, show_add_station_modal: false)}

      {:error, :invalid_station} ->
        {:noreply, assign(socket, modal_step: :input, modal_error: "Failed to create station. Please try again.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        error = changeset_error_message(changeset)
        {:noreply, assign(socket, modal_step: :input, modal_error: error)}

      {:error, _reason} ->
        {:noreply, assign(socket, modal_step: :input, modal_error: "An error occurred. Please try again.")}
    end
  end

  def handle_event("reset_add_station", _params, socket) do
    {:noreply,
     assign(socket,
       modal_step: :input,
       modal_code: "",
       modal_loading: false,
       modal_error: nil,
       modal_station_info: nil
     )}
  end

  def handle_event("toggle_monitoring", %{"code" => code}, socket) do
    toggle_station_field(socket, code, :monitoring_enabled)
  end

  def handle_event("toggle_auto_buy", %{"code" => code}, socket) do
    toggle_station_field(socket, code, :auto_buy_enabled)
  end

  def handle_event("update_station_settings", %{"code" => code} = params, socket) do
    station = Enum.find(socket.assigns.stations, &(&1.code == code))

    if station do
      attrs =
        %{}
        |> maybe_put(:max_buy_price, params["max_buy_price"])
        |> maybe_put(:buy_amount_usdc, params["buy_amount_usdc"])

      case Stations.update_station(station, attrs) do
        {:ok, _updated} -> {:noreply, socket}
        {:error, _} -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("sell_position", %{"position_id" => _position_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.dashboard_header balance={@balance} wallet_address={@wallet_address} />

      <!-- Portfolio Summary (placeholder) -->
      <div class="rounded-lg border border-zinc-200 bg-zinc-50 p-4">
        <p class="text-sm text-zinc-500">Portfolio summary will appear here</p>
      </div>

      <!-- Station Cards -->
      <div class="space-y-4">
        <.station_card
          :for={station <- @stations}
          station={station}
          clusters={Map.get(@clusters_by_station, station.code, [])}
          positions_by_cluster={@positions_by_cluster}
          balance={@balance}
        />
      </div>

      <div :if={@stations == []} class="text-center py-12 text-zinc-400">
        <p class="text-lg">No stations yet. Add one to get started.</p>
      </div>

      <!-- Signal Feed (placeholder) -->
      <div class="rounded-lg border border-zinc-200 bg-white p-4">
        <h3 class="text-sm font-semibold text-zinc-700 mb-2">Signal Feed</h3>
        <p class="text-sm text-zinc-400">Mispricing signals will appear here</p>
      </div>

      <.add_station_modal
        show={@show_add_station_modal}
        step={@modal_step}
        code={@modal_code}
        loading={@modal_loading}
        error={@modal_error}
        station_info={@modal_station_info}
      />
    </div>
    """
  end

  defp subscribe_to_topics(stations) do
    PubSubHelper.subscribe(PubSubHelper.stations())
    PubSubHelper.subscribe(PubSubHelper.portfolio_balance_update())
    PubSubHelper.subscribe(PubSubHelper.portfolio_position_update())

    Enum.each(stations, &subscribe_station/1)
  end

  defp subscribe_station(station) do
    PubSubHelper.subscribe(PubSubHelper.station_new_event(station.code))
    PubSubHelper.subscribe(PubSubHelper.station_forecast_update(station.code))
    PubSubHelper.subscribe(PubSubHelper.station_signal(station.code))
    PubSubHelper.subscribe(PubSubHelper.station_auto_buy(station.code))
    PubSubHelper.subscribe(PubSubHelper.station_price_update(station.code))
  end

  defp toggle_station_field(socket, code, field) do
    station = Enum.find(socket.assigns.stations, &(&1.code == code))

    if station do
      current_value = Map.get(station, field)
      Stations.update_station(station, %{field => !current_value})
    end

    {:noreply, socket}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map

  defp maybe_put(map, key, value) when is_binary(value) do
    case Float.parse(value) do
      {num, _} -> Map.put(map, key, num)
      :error -> map
    end
  end

  defp changeset_error_message(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end
end
