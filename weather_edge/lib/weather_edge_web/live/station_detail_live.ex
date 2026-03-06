defmodule WeatherEdgeWeb.StationDetailLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.Stations
  alias WeatherEdge.Markets.MarketCluster
  alias WeatherEdge.PubSubHelper

  @impl true
  def mount(%{"code" => code, "event_id" => event_id}, _session, socket) do
    case Stations.get_by_code(code) do
      {:ok, station} ->
        cluster = WeatherEdge.Repo.get(MarketCluster, event_id)

        if connected?(socket) do
          PubSubHelper.subscribe(PubSubHelper.station_forecast_update(code))
          PubSubHelper.subscribe(PubSubHelper.station_price_update(code))
          PubSubHelper.subscribe(PubSubHelper.station_signal(code))
          PubSubHelper.subscribe(PubSubHelper.station_auto_buy(code))
          PubSubHelper.subscribe(PubSubHelper.portfolio_position_update())
        end

        {:ok,
         assign(socket,
           station: station,
           cluster: cluster,
           page_title: "#{code} - #{cluster && cluster.target_date}"
         )}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Station not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center gap-4">
        <.link navigate={~p"/"} class="text-sm text-blue-600 hover:underline">&larr; Back to Dashboard</.link>
      </div>

      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-zinc-900">
          <%= @station.code %> - <%= @station.city %>
        </h1>
      </div>

      <div :if={@cluster} class="space-y-4">
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h2 class="text-lg font-semibold text-zinc-700 mb-2">
            Event: <%= @cluster.target_date %>
          </h2>
          <p class="text-sm text-zinc-500">Event ID: <%= @cluster.event_id %></p>
        </div>

        <!-- Temperature Distribution (placeholder) -->
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-2">Temperature Distribution</h3>
          <p class="text-sm text-zinc-400">Model probability vs market price will appear here</p>
        </div>

        <!-- Model Breakdown (placeholder) -->
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-2">Model Breakdown</h3>
          <p class="text-sm text-zinc-400">Per-model predictions will appear here</p>
        </div>

        <!-- Orderbook (placeholder) -->
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-2">Orderbook</h3>
          <p class="text-sm text-zinc-400">Best bid/ask will appear here</p>
        </div>

        <!-- Current METAR (placeholder) -->
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-2">Current METAR Observation</h3>
          <p class="text-sm text-zinc-400">Temperature, wind, humidity will appear here</p>
        </div>

        <!-- Action Buttons (placeholder) -->
        <div class="flex gap-4">
          <button class="rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-500">
            SELL POSITION
          </button>
          <button class="rounded-lg bg-green-600 px-4 py-2 text-sm font-semibold text-white hover:bg-green-500">
            BUY MORE
          </button>
        </div>
      </div>

      <div :if={is_nil(@cluster)} class="text-center py-12 text-zinc-400">
        <p class="text-lg">Event not found.</p>
      </div>
    </div>
    """
  end
end
