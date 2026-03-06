defmodule WeatherEdgeWeb.StationDetailLive do
  use WeatherEdgeWeb, :live_view

  import Ecto.Query

  alias WeatherEdge.{Repo, Stations, Forecasts}
  alias WeatherEdge.Markets.MarketCluster
  alias WeatherEdge.Trading.{Position, PositionTracker}
  alias WeatherEdge.Probability.{Engine, Distribution}
  alias WeatherEdge.Forecasts.MetarClient
  alias WeatherEdge.PubSubHelper

  @impl true
  def mount(%{"code" => code, "event_id" => event_id}, _session, socket) do
    case Stations.get_by_code(code) do
      {:ok, station} ->
        cluster = Repo.get(MarketCluster, event_id)

        if connected?(socket) do
          PubSubHelper.subscribe(PubSubHelper.station_forecast_update(code))
          PubSubHelper.subscribe(PubSubHelper.station_price_update(code))
          PubSubHelper.subscribe(PubSubHelper.station_signal(code))
          PubSubHelper.subscribe(PubSubHelper.station_auto_buy(code))
          PubSubHelper.subscribe(PubSubHelper.portfolio_position_update())
          send(self(), :load_data)
        end

        position = load_position(cluster)

        {:ok,
         assign(socket,
           station: station,
           cluster: cluster,
           position: position,
           distribution: nil,
           model_snapshots: [],
           market_health: nil,
           orderbook: nil,
           metar: nil,
           todays_high: nil,
           loading: true,
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
  def handle_info(:load_data, socket) do
    %{station: station, cluster: cluster, position: position} = socket.assigns

    if cluster do
      distribution = compute_distribution(station.code, cluster, station.temp_unit || "C")
      model_snapshots = load_model_snapshots(station.code, cluster.target_date)
      market_health = compute_market_health(cluster)
      orderbook = load_orderbook(position, cluster)
      metar = load_metar(station.code)
      todays_high = load_todays_high(station.code)

      {:noreply,
       assign(socket,
         distribution: distribution,
         model_snapshots: model_snapshots,
         market_health: market_health,
         orderbook: orderbook,
         metar: metar,
         todays_high: todays_high,
         loading: false
       )}
    else
      {:noreply, assign(socket, loading: false)}
    end
  end

  def handle_info({:position_updated, updated_position}, socket) do
    if socket.assigns.position && updated_position.id == socket.assigns.position.id do
      {:noreply, assign(socket, position: updated_position)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:forecast_updated, _station_code}, socket) do
    send(self(), :load_data)
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("sell_position", _params, socket) do
    case socket.assigns.position do
      %Position{status: "open"} = position ->
        case PositionTracker.sell_position(position) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(position: updated)
             |> put_flash(:info, "Sell order placed")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Sell failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "No open position to sell")}
    end
  end

  def handle_event("buy_more", _params, socket) do
    {:noreply, put_flash(socket, :info, "Use the auto-buyer or place orders via the trading module")}
  end

  # --- Data Loading ---

  defp load_position(nil), do: nil

  defp load_position(cluster) do
    Position
    |> where([p], p.market_cluster_id == ^cluster.id and p.status == "open")
    |> limit(1)
    |> Repo.one()
  end

  defp compute_distribution(station_code, cluster, temp_unit) do
    case Engine.compute_distribution(station_code, cluster.target_date, temp_unit: temp_unit) do
      {:ok, dist} -> dist
      {:error, _} -> nil
    end
  end

  defp load_model_snapshots(station_code, target_date) do
    Forecasts.latest_snapshots(station_code, target_date)
  end

  defp compute_market_health(cluster) do
    outcomes = parse_outcomes(cluster.outcomes)
    yes_sum = Enum.reduce(outcomes, 0.0, fn o, acc -> acc + (o["yes_price"] || 0.0) end)
    deviation = abs(yes_sum - 1.0)
    %{yes_sum: yes_sum, deviation: deviation, healthy: deviation <= 0.05}
  end

  defp load_orderbook(nil, _cluster), do: nil

  defp load_orderbook(position, _cluster) do
    case clob_client().get_orderbook(position.token_id) do
      {:ok, book} -> book
      {:error, _} -> nil
    end
  end

  defp load_metar(station_code) do
    case MetarClient.get_current_conditions(station_code) do
      {:ok, conditions} -> conditions
      {:error, _} -> nil
    end
  end

  defp load_todays_high(station_code) do
    case MetarClient.get_todays_high(station_code) do
      {:ok, high} -> high
      {:error, _} -> nil
    end
  end

  defp parse_outcomes(outcomes) when is_list(outcomes), do: outcomes
  defp parse_outcomes(_), do: []

  # --- Helpers ---

  defp format_prob(nil), do: "-"
  defp format_prob(prob), do: "#{:erlang.float_to_binary(prob * 100, decimals: 1)}%"

  defp format_price(nil), do: "-"
  defp format_price(price) when is_float(price), do: :erlang.float_to_binary(price, decimals: 2)
  defp format_price(price) when is_binary(price), do: price
  defp format_price(price) when is_integer(price), do: "#{price}.00"

  defp format_temp(temp) when is_float(temp), do: "#{round(temp)}C (#{:erlang.float_to_binary(temp, decimals: 1)}C raw)"
  defp format_temp(temp) when is_integer(temp), do: "#{temp}C"
  defp format_temp(_), do: "-"

  defp bar_width(prob) when is_float(prob) and prob > 0, do: max(round(prob * 100 * 3), 2)
  defp bar_width(_), do: 2

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
        <span :if={@cluster} class="text-sm text-zinc-500">
          Target: <%= @cluster.target_date %> (<%= Date.diff(@cluster.target_date, Date.utc_today()) %> days)
        </span>
      </div>

      <div :if={@loading} class="text-center py-12 text-zinc-400">
        <p class="text-lg">Loading data...</p>
      </div>

      <div :if={@cluster && !@loading} class="space-y-4">
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <div class="flex items-center justify-between">
            <div>
              <h2 class="text-lg font-semibold text-zinc-700 mb-1">
                <%= @cluster.title || "Event: #{@cluster.target_date}" %>
              </h2>
              <p class="text-xs text-zinc-400">Event ID: <%= @cluster.event_id %></p>
            </div>
            <div :if={@todays_high} class="text-right">
              <% display_high = if @station.temp_unit == "F", do: @todays_high * 9 / 5 + 32, else: @todays_high %>
              <p class="text-xs text-zinc-500">Observed High (24h)</p>
              <p class="text-3xl font-bold text-zinc-900"><%= round(display_high) %>°<%= @station.temp_unit || "C" %></p>
              <p class="text-xs text-zinc-400"><%= :erlang.float_to_binary(display_high / 1, decimals: 1) %>°<%= @station.temp_unit || "C" %> raw</p>
            </div>
          </div>
        </div>

        <%!-- Temperature Distribution --%>
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-3">Temperature Distribution</h3>
          <%= if @distribution do %>
            <div class="space-y-1">
              <div class="grid grid-cols-[80px_60px_60px_1fr] gap-2 text-xs font-medium text-zinc-500 mb-2">
                <span>Outcome</span>
                <span class="text-right">Model</span>
                <span class="text-right">Market</span>
                <span>Distribution</span>
              </div>
              <%= for {label, model_prob} <- merged_distribution(@distribution, @cluster) do %>
                <% market_price = find_market_price(@cluster, label) %>
                <% edge = if market_price, do: model_prob - market_price, else: nil %>
                <div class="grid grid-cols-[80px_60px_60px_1fr] gap-2 items-center text-sm">
                  <span class="font-medium text-zinc-800"><%= label %></span>
                  <span class="text-right text-zinc-600"><%= format_prob(model_prob) %></span>
                  <span class="text-right text-zinc-600"><%= if market_price, do: format_prob(market_price), else: "-" %></span>
                  <div class="flex items-center gap-2">
                    <div class="h-4 rounded bg-blue-400" style={"width: #{bar_width(model_prob)}px"}></div>
                    <div :if={market_price} class="h-4 rounded bg-amber-400 opacity-60" style={"width: #{bar_width(market_price)}px"}></div>
                    <span :if={edge} class={[
                      "text-xs font-medium ml-1",
                      edge > 0.05 && "text-green-600",
                      edge < -0.05 && "text-red-500",
                      edge >= -0.05 && edge <= 0.05 && "text-zinc-400"
                    ]}>
                      <%= if edge > 0, do: "+", else: "" %><%= :erlang.float_to_binary(edge * 100, decimals: 1) %>%
                    </span>
                  </div>
                </div>
              <% end %>
            </div>
            <div class="mt-2 flex gap-4 text-xs text-zinc-400">
              <span class="flex items-center gap-1"><span class="inline-block w-3 h-3 rounded bg-blue-400"></span> Model</span>
              <span class="flex items-center gap-1"><span class="inline-block w-3 h-3 rounded bg-amber-400 opacity-60"></span> Market</span>
            </div>
          <% else %>
            <p class="text-sm text-zinc-400">No forecast data available yet</p>
          <% end %>
        </div>

        <%!-- Model Breakdown --%>
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-3">Model Breakdown</h3>
          <%= if @model_snapshots != [] do %>
            <div class="space-y-1">
              <%= for snapshot <- @model_snapshots do %>
                <div class="flex items-center justify-between text-sm py-1">
                  <span class="font-medium text-zinc-700 uppercase"><%= snapshot.model %></span>
                  <span class="text-zinc-600"><%= format_temp(snapshot.max_temp_c) %></span>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-sm text-zinc-400">No model forecasts available</p>
          <% end %>
        </div>

        <%!-- Market Cluster Health --%>
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-3">Market Cluster Health</h3>
          <%= if @market_health do %>
            <div class="flex items-center gap-3">
              <span class={[
                "text-lg font-bold",
                @market_health.healthy && "text-green-600",
                !@market_health.healthy && "text-amber-600"
              ]}>
                Sum YES: <%= :erlang.float_to_binary(@market_health.yes_sum, decimals: 3) %>
              </span>
              <span :if={!@market_health.healthy} class="text-xs text-amber-600 font-medium">
                Deviation: <%= :erlang.float_to_binary(@market_health.deviation, decimals: 3) %> (> 0.05)
              </span>
              <span :if={@market_health.healthy} class="text-xs text-green-600">Healthy</span>
            </div>
          <% end %>
        </div>

        <%!-- Orderbook --%>
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-3">
            Orderbook
            <span :if={@position} class="text-xs font-normal text-zinc-400 ml-1">(<%= @position.outcome_label %>)</span>
          </h3>
          <%= if @orderbook do %>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <p class="text-xs text-zinc-500 mb-1">Best Bid</p>
                <%= if @orderbook.bids != [] do %>
                  <% best_bid = List.first(@orderbook.bids) %>
                  <p class="text-lg font-bold text-green-600"><%= format_price(best_bid.price) %></p>
                  <p class="text-xs text-zinc-400">Size: <%= format_price(best_bid.size) %></p>
                <% else %>
                  <p class="text-sm text-zinc-400">No bids</p>
                <% end %>
              </div>
              <div>
                <p class="text-xs text-zinc-500 mb-1">Best Ask</p>
                <%= if @orderbook.asks != [] do %>
                  <% best_ask = List.first(@orderbook.asks) %>
                  <p class="text-lg font-bold text-red-500"><%= format_price(best_ask.price) %></p>
                  <p class="text-xs text-zinc-400">Size: <%= format_price(best_ask.size) %></p>
                <% else %>
                  <p class="text-sm text-zinc-400">No asks</p>
                <% end %>
              </div>
            </div>
            <%= if @orderbook.bids != [] && @orderbook.asks != [] do %>
              <% spread = List.first(@orderbook.asks).price - List.first(@orderbook.bids).price %>
              <p class="text-xs text-zinc-400 mt-2">
                Spread: <%= :erlang.float_to_binary(spread, decimals: 3) %>
              </p>
            <% end %>
          <% else %>
            <p class="text-sm text-zinc-400">
              <%= if @position, do: "Orderbook unavailable", else: "No position - orderbook not loaded" %>
            </p>
          <% end %>
        </div>

        <%!-- Current METAR Observation --%>
        <div class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-3">Current METAR Observation</h3>
          <%= if @metar do %>
            <div class="grid grid-cols-3 gap-4">
              <div>
                <p class="text-xs text-zinc-500">Temperature</p>
                <p class="text-lg font-bold text-zinc-800">
                  <%= if @metar.temperature_c, do: "#{round(@metar.temperature_c)}C", else: "-" %>
                </p>
              </div>
              <div>
                <p class="text-xs text-zinc-500">Wind</p>
                <p class="text-lg font-bold text-zinc-800">
                  <%= if @metar.wind_speed_kt, do: "#{round(@metar.wind_speed_kt)} kt", else: "-" %>
                  <span :if={@metar.wind_direction} class="text-sm font-normal text-zinc-500">
                    @ <%= @metar.wind_direction %>°
                  </span>
                </p>
              </div>
              <div>
                <p class="text-xs text-zinc-500">Humidity</p>
                <p class="text-lg font-bold text-zinc-800">
                  <%= if @metar.humidity, do: "#{@metar.humidity}%", else: "-" %>
                </p>
              </div>
            </div>
            <p :if={@metar.observed_at} class="text-xs text-zinc-400 mt-2">
              Observed: <%= @metar.observed_at %>
            </p>
          <% else %>
            <p class="text-sm text-zinc-400">METAR data unavailable</p>
          <% end %>
        </div>

        <%!-- Position Info --%>
        <div :if={@position} class="rounded-lg border border-zinc-200 bg-white p-4">
          <h3 class="text-sm font-semibold text-zinc-700 mb-3">Position</h3>
          <div class="grid grid-cols-4 gap-4 text-sm">
            <div>
              <p class="text-xs text-zinc-500">Outcome</p>
              <p class="font-medium"><%= @position.outcome_label %> (<%= @position.side %>)</p>
            </div>
            <div>
              <p class="text-xs text-zinc-500">Tokens / Avg Price</p>
              <p class="font-medium"><%= format_price(@position.tokens) %> @ <%= format_price(@position.avg_buy_price) %></p>
            </div>
            <div>
              <p class="text-xs text-zinc-500">Current Price</p>
              <p class="font-medium"><%= format_price(@position.current_price) %></p>
            </div>
            <div>
              <p class="text-xs text-zinc-500">Unrealized P&L</p>
              <p class={[
                "font-bold",
                (@position.unrealized_pnl || 0) > 0 && "text-green-600",
                (@position.unrealized_pnl || 0) < 0 && "text-red-500",
                (@position.unrealized_pnl || 0) == 0 && "text-zinc-500"
              ]}>
                $<%= format_price(@position.unrealized_pnl || 0.0) %>
              </p>
            </div>
          </div>
          <p :if={@position.recommendation} class="mt-2 text-xs text-zinc-500">
            Recommendation: <span class="font-semibold text-zinc-700"><%= @position.recommendation %></span>
          </p>
        </div>

        <%!-- Action Buttons
          <div class="flex gap-4">
            <button
              :if={@position && @position.status == "open"}
              phx-click="sell_position"
              data-confirm="Are you sure you want to sell this position?"
              class="rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-500"
            >
              SELL POSITION
            </button>
            <button
              phx-click="buy_more"
              class="rounded-lg bg-green-600 px-4 py-2 text-sm font-semibold text-white hover:bg-green-500"
            >
              BUY MORE
            </button>
          </div>
        --%>
      </div>

      <div :if={is_nil(@cluster) && !@loading} class="text-center py-12 text-zinc-400">
        <p class="text-lg">Event not found.</p>
      </div>
    </div>
    """
  end

  defp find_market_price(cluster, label) do
    outcomes = parse_outcomes(cluster.outcomes)

    match =
      Enum.find(outcomes, fn o ->
        o["outcome_label"] == label || extract_temp_label(o["outcome_label"]) == label
      end)

    case match do
      %{"yes_price" => price} when is_number(price) -> price
      %{"yes_price" => price} when is_binary(price) ->
        case Float.parse(price) do
          {f, _} -> f
          :error -> nil
        end
      _ -> nil
    end
  end

  defp extract_temp_label(nil), do: nil

  defp extract_temp_label(label) when is_binary(label) do
    case Regex.run(~r/(\d+)\s*°?\s*([CF])\s+(or below|or higher)/i, label) do
      [_, temp, unit, suffix] ->
        "#{temp}#{String.upcase(unit)} #{String.downcase(suffix)}"

      _ ->
        case Regex.run(~r/(\d+)\s*°?\s*([CF])/i, label) do
          [_, temp, unit] -> "#{temp}#{String.upcase(unit)}"
          _ -> label
        end
    end
  end

  defp merged_distribution(distribution, cluster) do
    model_entries = Distribution.top_n(distribution, 20)
    model_labels = MapSet.new(model_entries, fn {label, _} -> label end)

    # Get market outcomes not already in model distribution
    market_only =
      cluster.outcomes
      |> parse_outcomes()
      |> Enum.map(fn o -> extract_temp_label(o["outcome_label"]) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(fn label -> MapSet.member?(model_labels, label) end)
      |> Enum.uniq()
      |> Enum.map(fn label -> {label, 0.0} end)

    # Combine and sort: model entries first (by prob desc), then market-only (by label)
    model_entries ++ Enum.sort_by(market_only, fn {label, _} -> label end)
  end

  defp clob_client, do: Application.get_env(:weather_edge, :clob_client, WeatherEdge.Trading.ClobClient)
end
