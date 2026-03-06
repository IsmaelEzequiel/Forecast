defmodule WeatherEdgeWeb.DashboardLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.Stations
  alias WeatherEdge.Markets
  alias WeatherEdge.Trading.Position
  alias WeatherEdge.PubSubHelper

  import Ecto.Query

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

    if connected?(socket) do
      subscribe_to_topics(stations)
    end

    {:ok,
     assign(socket,
       stations: stations,
       clusters_by_station: clusters_by_station,
       positions: positions,
       signals: [],
       balance: nil,
       show_add_station_modal: false
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

    {:noreply, assign(socket, positions: positions)}
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

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_add_station_modal", _params, socket) do
    {:noreply, assign(socket, show_add_station_modal: !socket.assigns.show_add_station_modal)}
  end

  def handle_event("sell_position", %{"position_id" => _position_id}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-zinc-900">WEATHER EDGE</h1>
        <div class="flex items-center gap-4">
          <span :if={@balance} class="text-sm font-medium text-zinc-600">
            $<%= :erlang.float_to_binary(@balance, decimals: 2) %> USDC
          </span>
          <button
            phx-click="toggle_add_station_modal"
            class="rounded-lg bg-zinc-900 px-3 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
          >
            + Add Station
          </button>
        </div>
      </div>

      <!-- Portfolio Summary (placeholder) -->
      <div class="rounded-lg border border-zinc-200 bg-zinc-50 p-4">
        <p class="text-sm text-zinc-500">Portfolio summary will appear here</p>
      </div>

      <!-- Station Cards -->
      <div class="space-y-4">
        <div :for={station <- @stations} class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-lg font-semibold text-zinc-900">
              <%= station.code %> - <%= station.city %>
            </h2>
            <span class={"text-xs px-2 py-1 rounded-full #{if station.monitoring_enabled, do: "bg-green-100 text-green-700", else: "bg-zinc-100 text-zinc-500"}"}>
              <%= if station.monitoring_enabled, do: "Monitoring ON", else: "Monitoring OFF" %>
            </span>
          </div>

          <div :if={clusters = Map.get(@clusters_by_station, station.code, [])}>
            <div :for={cluster <- clusters} class="ml-4 mt-2 rounded border border-zinc-100 bg-zinc-50 p-3">
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-zinc-700">
                  <%= cluster.target_date %>
                </span>
                <.link
                  navigate={~p"/stations/#{station.code}/events/#{cluster.id}"}
                  class="text-xs text-blue-600 hover:underline"
                >
                  View Details
                </.link>
              </div>
            </div>
            <p :if={clusters == []} class="ml-4 mt-2 text-sm text-zinc-400">No active events</p>
          </div>
        </div>
      </div>

      <div :if={@stations == []} class="text-center py-12 text-zinc-400">
        <p class="text-lg">No stations yet. Add one to get started.</p>
      </div>

      <!-- Signal Feed (placeholder) -->
      <div class="rounded-lg border border-zinc-200 bg-white p-4">
        <h3 class="text-sm font-semibold text-zinc-700 mb-2">Signal Feed</h3>
        <p class="text-sm text-zinc-400">Mispricing signals will appear here</p>
      </div>
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
end
