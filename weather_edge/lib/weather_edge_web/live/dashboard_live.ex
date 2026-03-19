defmodule WeatherEdgeWeb.DashboardLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.Stations
  alias WeatherEdge.Markets
  alias WeatherEdge.Trading.Position
  alias WeatherEdge.PubSubHelper

  import WeatherEdgeWeb.Components.HeaderComponent
  import WeatherEdgeWeb.Components.AddStationModalComponent
  import WeatherEdgeWeb.Components.StationCardComponent
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
      :timer.send_interval(5_000, self(), :tick_workers)
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
       balance: cached_balance,
       wallet_address: wallet_address,
       show_add_station_modal: false,
       modal_step: :input,
       modal_code: "",
       modal_loading: false,
       modal_error: nil,
       modal_station_info: nil,
       modal_temp_unit: "C",
       worker_tick: 0
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

  def handle_info(:tick_workers, socket) do
    {:noreply, assign(socket, :worker_tick, System.monotonic_time())}
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

  def handle_event("trigger_worker", %{"worker" => worker}, socket) do
    worker_module = worker_module(worker)

    if worker_module do
      worker_module.new(%{}) |> Oban.insert()
      {:noreply, put_flash(socket, :info, "#{worker_label(worker)} triggered")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("scan_station", %{"code" => code}, socket) do
    %{station_code: code}
    |> WeatherEdge.Workers.EventScannerWorker.new(queue: :scanner)
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Scanning events for #{code}...")}
  end

  def handle_event("refresh_forecasts", %{"code" => code}, socket) do
    %{station_code: code}
    |> WeatherEdge.Workers.ForecastRefreshWorker.new(queue: :forecasts)
    |> Oban.insert()

    {:noreply, put_flash(socket, :info, "Refreshing forecasts for #{code}...")}
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

      <!-- Worker Controls -->
      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider mb-3">Workers</h3>
        <div class="flex flex-wrap gap-2">
          <.worker_button label="Scan Events" desc="Find new Polymarket temperature markets" worker="event_scanner" last_run={job_ago(:event_scanner)} running={job_running?(:event_scanner)} tick={@worker_tick} />
          <.worker_button label="Refresh Forecasts" desc="Fetch predictions from all 8 weather models (updates Model Breakdown)" worker="forecast_refresh" last_run={job_ago(:forecast_refresh)} running={job_running?(:forecast_refresh)} tick={@worker_tick} />
          <.worker_button label="Snapshot Prices" desc="Save current Polymarket prices for P&L tracking" worker="price_snapshot" last_run={job_ago(:price_snapshot)} running={job_running?(:price_snapshot)} tick={@worker_tick} />
          <.worker_button label="Monitor Positions" desc="Check open positions and update unrealized P&L" worker="position_monitor" last_run={job_ago(:position_monitor)} running={job_running?(:position_monitor)} tick={@worker_tick} />
          <.worker_button label="Resolve Events" desc="Close past events, fetch actual temps, finalize P&L" worker="resolution" last_run={job_ago(:resolution)} running={job_running?(:resolution)} tick={@worker_tick} />
          <.worker_button label="Dutch Buyer" desc="Execute dutching strategy on new events (multi-outcome YES)" worker="dutch_buyer" last_run={job_ago(:dutch_buyer)} running={job_running?(:dutch_buyer)} tick={@worker_tick} />
          <.worker_button label="Dutch Monitor" desc="Update prices and sell/hold recommendations for open dutch positions" worker="dutch_monitor" last_run={job_ago(:dutch_monitor)} running={job_running?(:dutch_monitor)} tick={@worker_tick} />
          <.worker_button label="Dutch Resolver" desc="Resolve dutch groups when markets close" worker="dutch_resolver" last_run={job_ago(:dutch_resolver)} running={job_running?(:dutch_resolver)} tick={@worker_tick} />
        </div>
      </div>

      <.portfolio_summary positions={@all_positions} sidecar_positions={@sidecar_positions} balance={@balance} />

      <!-- Station Cards -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
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

  attr :label, :string, required: true
  attr :desc, :string, required: true
  attr :worker, :string, required: true
  attr :last_run, :string, required: true
  attr :running, :boolean, required: true
  attr :tick, :integer, required: true

  defp worker_button(assigns) do
    ~H"""
    <button
      phx-click="trigger_worker"
      phx-value-worker={@worker}
      class={"flex flex-col items-start rounded-md border px-3 py-2 text-left transition-colors #{if @running, do: "border-green-400 dark:border-green-600 bg-green-50 dark:bg-green-950", else: "border-zinc-200 dark:border-zinc-600 bg-zinc-50 dark:bg-zinc-800 hover:bg-zinc-100 dark:hover:bg-zinc-700"}"}
      title={@desc}
      disabled={@running}
    >
      <div class="flex items-center gap-2">
        <span :if={@running} class="inline-block w-2 h-2 rounded-full bg-green-500 animate-pulse"></span>
        <span class="text-xs font-medium text-zinc-700 dark:text-zinc-300"><%= @label %></span>
        <span :if={@running} class="text-xs font-semibold text-green-600 dark:text-green-400">Running</span>
        <span :if={!@running} class="text-xs text-zinc-400 dark:text-zinc-500"><%= @last_run %></span>
      </div>
      <span class="text-[10px] text-zinc-400 dark:text-zinc-500 mt-0.5"><%= @desc %></span>
    </button>
    """
  end

  defp job_ago(key), do: WeatherEdge.JobTracker.time_ago(WeatherEdge.JobTracker.last_run(key))
  defp job_running?(key), do: WeatherEdge.JobTracker.running?(key)

  defp worker_module("event_scanner"), do: WeatherEdge.Workers.EventScannerWorker
  defp worker_module("forecast_refresh"), do: WeatherEdge.Workers.ForecastRefreshWorker
  defp worker_module("price_snapshot"), do: WeatherEdge.Workers.PriceSnapshotWorker
  defp worker_module("position_monitor"), do: WeatherEdge.Workers.PositionMonitorWorker
  defp worker_module("resolution"), do: WeatherEdge.Workers.ResolutionWorker
  defp worker_module("dutch_buyer"), do: WeatherEdge.Workers.DutchBuyerWorker
  defp worker_module("dutch_monitor"), do: WeatherEdge.Workers.DutchMonitorWorker
  defp worker_module("dutch_resolver"), do: WeatherEdge.Workers.DutchResolverWorker
  defp worker_module(_), do: nil

  defp worker_label("event_scanner"), do: "Event Scanner"
  defp worker_label("forecast_refresh"), do: "Forecast Refresh"
  defp worker_label("price_snapshot"), do: "Price Snapshot"
  defp worker_label("position_monitor"), do: "Position Monitor"
  defp worker_label("resolution"), do: "Resolution"
  defp worker_label("dutch_buyer"), do: "Dutch Buyer"
  defp worker_label("dutch_monitor"), do: "Dutch Monitor"
  defp worker_label("dutch_resolver"), do: "Dutch Resolver"
  defp worker_label(w), do: w

  defp changeset_error_message(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end
end
