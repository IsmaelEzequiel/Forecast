defmodule WeatherEdgeWeb.DashboardLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.Stations
  alias WeatherEdge.Markets
  alias WeatherEdge.Trading.Position
  alias WeatherEdge.PubSubHelper

  import WeatherEdgeWeb.Components.HeaderComponent
  import WeatherEdgeWeb.Components.AddStationModalComponent
  import WeatherEdgeWeb.Components.StationCardComponent
  import WeatherEdgeWeb.Components.SignalFeedComponent
  import WeatherEdgeWeb.Components.PortfolioSummaryComponent

  @impl true
  def mount(_params, _session, socket) do
    stations = Stations.list_stations()

    clusters_by_station =
      Enum.into(stations, %{}, fn station ->
        {station.code, Markets.active_clusters_for_station(station.code)}
      end)

    all_positions = WeatherEdge.Repo.all(Position)

    positions =
      Enum.filter(all_positions, &(&1.status == "open"))

    positions_by_cluster =
      Enum.into(positions, %{}, fn p -> {p.market_cluster_id, p} end)

    if connected?(socket) do
      subscribe_to_topics(stations)
    end

    wallet_address = Application.get_env(:weather_edge, :polymarket)[:wallet_address]
    cached_balance = :persistent_term.get(:sidecar_balance, nil)
    sidecar_positions = :persistent_term.get(:sidecar_positions, [])

    {:ok,
     assign(socket,
       stations: stations,
       clusters_by_station: clusters_by_station,
       all_positions: all_positions,
       positions: positions,
       positions_by_cluster: positions_by_cluster,
       sidecar_positions: sidecar_positions,
       signals: WeatherEdge.Signals.list_recent(limit: 50),
       balance: cached_balance,
       wallet_address: wallet_address,
       show_add_station_modal: false,
       modal_step: :input,
       modal_code: "",
       modal_loading: false,
       modal_error: nil,
       modal_station_info: nil,
       modal_temp_unit: "C"
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
    all_positions =
      Enum.map(socket.assigns.all_positions, fn p ->
        if p.id == position.id, do: position, else: p
      end)

    positions =
      Enum.filter(all_positions, &(&1.status == "open"))

    positions_by_cluster =
      Enum.into(positions, %{}, fn p -> {p.market_cluster_id, p} end)

    {:noreply, assign(socket, all_positions: all_positions, positions: positions, positions_by_cluster: positions_by_cluster)}
  end

  def handle_info({:positions_synced, positions}, socket) do
    # Reload DB positions to pick up any that were closed by reconciliation
    all_positions = WeatherEdge.Repo.all(Position)
    open_positions = Enum.filter(all_positions, &(&1.status == "open"))
    positions_by_cluster = Enum.into(open_positions, %{}, fn p -> {p.market_cluster_id, p} end)

    {:noreply,
     assign(socket,
       sidecar_positions: positions,
       all_positions: all_positions,
       positions: open_positions,
       positions_by_cluster: positions_by_cluster
     )}
  end

  def handle_info({:forecast_updated, _station_code}, socket) do
    {:noreply, socket}
  end

  def handle_info({:signal_detected, signal}, socket) do
    signals = [signal | socket.assigns.signals] |> Enum.take(50)
    {:noreply, assign(socket, signals: signals)}
  end

  def handle_info({:auto_buy_executed, station_code, details}, socket) do
    auto_buy_signal =
      %{
        type: :auto_buy,
        station_code: station_code,
        outcome_label: details[:outcome_label] || "Unknown",
        market_price: details[:price],
        edge: nil,
        alert_level: nil,
        timestamp: DateTime.utc_now()
      }

    signals = [auto_buy_signal | socket.assigns.signals] |> Enum.take(50)
    {:noreply, assign(socket, signals: signals)}
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
       modal_station_info: nil,
       modal_temp_unit: "C"
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

  def handle_event("set_temp_unit", %{"unit" => unit}, socket) when unit in ["C", "F"] do
    {:noreply, assign(socket, modal_temp_unit: unit)}
  end

  def handle_event("confirm_add_station", _params, socket) do
    case Stations.create_station(%{code: socket.assigns.modal_code, temp_unit: socket.assigns.modal_temp_unit}) do
      {:ok, station} ->
        # Trigger immediate event scan for the new station
        %{station_code: station.code}
        |> WeatherEdge.Workers.EventScannerWorker.new(queue: :scanner)
        |> Oban.insert()

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
       modal_station_info: nil,
       modal_temp_unit: "C"
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

  def handle_event("scan_station", %{"code" => code}, socket) do
    %{station_code: code}
    |> WeatherEdge.Workers.EventScannerWorker.new(queue: :scanner)
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Scanning events for #{code}...")}
  end

  def handle_event("delete_station", %{"code" => code}, socket) do
    station = Enum.find(socket.assigns.stations, &(&1.code == code))

    if station do
      case Stations.delete_station(station) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "Station #{code} deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete station")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_cluster", %{"cluster_id" => cluster_id}, socket) do
    case WeatherEdge.Markets.delete_market_cluster(cluster_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Event deleted")
         |> assign(clusters: WeatherEdge.Markets.get_active_clusters())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete event")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.dashboard_header balance={@balance} wallet_address={@wallet_address} />

      <.portfolio_summary positions={@all_positions} sidecar_positions={@sidecar_positions} balance={@balance} />

      <!-- Station Cards -->
      <div class="grid grid-cols-2 gap-4">
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

      <.signal_feed signals={@signals} />

      <.add_station_modal
        show={@show_add_station_modal}
        step={@modal_step}
        code={@modal_code}
        loading={@modal_loading}
        error={@modal_error}
        station_info={@modal_station_info}
        temp_unit={@modal_temp_unit}
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
