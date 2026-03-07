defmodule WeatherEdgeWeb.AnalyticsLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.Calibration
  alias WeatherEdge.Calibration.BiasTracker
  alias WeatherEdge.Stations
  alias WeatherEdge.Markets
  alias WeatherEdge.Trading.Position
  alias WeatherEdge.Signals

  import Ecto.Query
  import WeatherEdgeWeb.Components.HeaderComponent

  @impl true
  def mount(_params, _session, socket) do
    daily_pnl = Calibration.daily_pnl(days: 30)
    summary = Calibration.summary_stats()
    stations = Stations.list_stations()

    station_stats =
      Enum.map(stations, fn s ->
        stats = BiasTracker.stats_for_station(s.code)
        Map.put(stats, :station_code, s.code)
      end)
      |> Enum.filter(fn s -> s.count > 0 end)

    cumulative_pnl = build_cumulative(daily_pnl)

    # Closed trades
    closed_positions =
      Position
      |> where([p], p.status != "open")
      |> order_by([p], desc: p.closed_at)
      |> limit(20)
      |> preload(:market_cluster)
      |> WeatherEdge.Repo.all()

    # Open positions
    open_positions =
      Position
      |> where([p], p.status == "open")
      |> order_by([p], desc: p.opened_at)
      |> preload(:market_cluster)
      |> WeatherEdge.Repo.all()

    # Recent signals
    recent_signals = Signals.list_recent(limit: 20)

    # Active clusters per station
    station_clusters =
      Enum.map(stations, fn s ->
        clusters = Markets.active_clusters_for_station(s.code)
        %{station: s, clusters: clusters}
      end)
      |> Enum.filter(fn sc -> sc.clusters != [] end)

    # Sidecar data
    sidecar_positions = :persistent_term.get(:sidecar_positions, [])

    wallet_address = Application.get_env(:weather_edge, :polymarket)[:wallet_address]
    cached_balance = :persistent_term.get(:sidecar_balance, nil)

    {:ok,
     assign(socket,
       daily_pnl: daily_pnl,
       cumulative_pnl: cumulative_pnl,
       summary: summary,
       station_stats: station_stats,
       recent_trades: closed_positions,
       open_positions: open_positions,
       sidecar_positions: sidecar_positions,
       recent_signals: recent_signals,
       station_clusters: station_clusters,
       balance: cached_balance,
       wallet_address: wallet_address
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.dashboard_header balance={@balance} wallet_address={@wallet_address} />

      <!-- Summary Stats -->
      <div class="grid grid-cols-2 lg:grid-cols-5 gap-4">
        <.stat_card label="Open Positions" value={"#{length(@open_positions)}"} />
        <.stat_card label="Events Resolved" value={"#{@summary.total_events}"} />
        <.stat_card label="Prediction Hit Rate" value={"#{Float.round(@summary.hit_rate * 100, 1)}%"} />
        <.stat_card label="Auto-Buy Trades" value={"#{@summary.auto_buy_count}"} />
        <.stat_card label="Auto-Buy P&L" value={"$#{format_pnl(@summary.auto_buy_total_pnl)}"} color={pnl_color(@summary.auto_buy_total_pnl)} />
      </div>

      <!-- P&L Chart -->
      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <h3 class="text-sm font-semibold text-zinc-700 dark:text-zinc-300 mb-4">Cumulative P&L (30 days)</h3>
        <.pnl_chart data={@cumulative_pnl} />
      </div>

      <!-- Open Positions -->
      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <h3 class="text-sm font-semibold text-zinc-700 dark:text-zinc-300 mb-4">
          Open Positions (<%= length(@open_positions) %>)
        </h3>
        <div :if={@open_positions == [] && @sidecar_positions == []} class="text-sm text-zinc-400 py-4 text-center">
          No open positions. Positions will appear here when you buy on Polymarket.
        </div>

        <!-- Sidecar (live Polymarket) positions -->
        <div :if={@sidecar_positions != []} class="mb-4">
          <p class="text-xs font-medium text-indigo-600 dark:text-indigo-400 mb-2">Live from Polymarket</p>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-zinc-200 dark:border-zinc-700 text-xs text-zinc-500 dark:text-zinc-400">
                  <th class="text-left py-2 pr-3">Outcome</th>
                  <th class="text-right py-2 px-3">Size</th>
                  <th class="text-right py-2 px-3">Avg Price</th>
                  <th class="text-right py-2 px-3">Current</th>
                  <th class="text-right py-2 px-3">Value</th>
                  <th class="text-right py-2 px-3">P&L</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={sp <- @sidecar_positions} class="border-b border-zinc-100 dark:border-zinc-800">
                  <td class="py-2 pr-3 font-medium text-zinc-900 dark:text-zinc-100"><%= sp["title"] || sp["outcome"] || "—" %></td>
                  <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400"><%= sp["size"] || "—" %></td>
                  <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= fmt_sidecar(sp["avgPrice"]) %></td>
                  <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= fmt_sidecar(sp["curPrice"]) %></td>
                  <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= fmt_sidecar(sp["currentValue"]) %></td>
                  <td class={"py-2 px-3 text-right font-semibold #{pnl_color(parse_num(sp["cashPnl"]))}"}>
                    $<%= fmt_sidecar(sp["cashPnl"]) %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- DB positions -->
        <div :if={@open_positions != []}>
          <p :if={@sidecar_positions != []} class="text-xs font-medium text-zinc-500 dark:text-zinc-400 mb-2">From Database</p>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-zinc-200 dark:border-zinc-700 text-xs text-zinc-500 dark:text-zinc-400">
                  <th class="text-left py-2 pr-3">Station</th>
                  <th class="text-left py-2 px-3">Outcome</th>
                  <th class="text-right py-2 px-3">Tokens</th>
                  <th class="text-right py-2 px-3">Avg Price</th>
                  <th class="text-right py-2 px-3">Current</th>
                  <th class="text-right py-2 px-3">Cost</th>
                  <th class="text-right py-2 px-3">Unrealized</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={pos <- @open_positions} class="border-b border-zinc-100 dark:border-zinc-800">
                  <td class="py-2 pr-3 font-mono font-semibold text-zinc-900 dark:text-zinc-100"><%= pos.station_code %></td>
                  <td class="py-2 px-3 text-zinc-600 dark:text-zinc-400">
                    <%= pos.outcome_label %>
                    <span class="text-xs text-zinc-400">(<%= pos.side %>)</span>
                  </td>
                  <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400"><%= format_price(pos.tokens) %></td>
                  <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= format_price(pos.avg_buy_price) %></td>
                  <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= format_price(pos.current_price) %></td>
                  <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= format_price(pos.total_cost_usdc) %></td>
                  <td class={"py-2 px-3 text-right font-semibold #{pnl_color(pos.unrealized_pnl)}"}>
                    <%= format_pnl(pos.unrealized_pnl) %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- Recent Signals -->
      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <h3 class="text-sm font-semibold text-zinc-700 dark:text-zinc-300 mb-4">
          Recent Signals (<%= length(@recent_signals) %>)
        </h3>
        <div :if={@recent_signals == []} class="text-sm text-zinc-400 py-4 text-center">
          No signals yet. Signals will appear when the mispricing scanner detects opportunities.
        </div>
        <div :if={@recent_signals != []} class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-zinc-200 dark:border-zinc-700 text-xs text-zinc-500 dark:text-zinc-400">
                <th class="text-left py-2 pr-3">Time</th>
                <th class="text-left py-2 px-3">Station</th>
                <th class="text-left py-2 px-3">Outcome</th>
                <th class="text-left py-2 px-3">Side</th>
                <th class="text-right py-2 px-3">Edge</th>
                <th class="text-right py-2 px-3">Model</th>
                <th class="text-right py-2 px-3">Market</th>
                <th class="text-left py-2 pl-3">Level</th>
                <th class="text-left py-2 pl-3">Confidence</th>
                <th class="text-right py-2 pl-3"></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={sig <- @recent_signals} class="border-b border-zinc-100 dark:border-zinc-800">
                <td class="py-2 pr-3 font-mono text-xs text-zinc-500 dark:text-zinc-400">
                  <%= if sig.computed_at, do: Calendar.strftime(sig.computed_at, "%H:%M"), else: "-" %>
                </td>
                <td class="py-2 px-3 font-mono font-semibold text-zinc-900 dark:text-zinc-100"><%= sig.station_code %></td>
                <td class="py-2 px-3 text-zinc-600 dark:text-zinc-400"><%= sig.outcome_label %></td>
                <td class="py-2 px-3">
                  <span class={["text-xs font-bold px-1.5 py-0.5 rounded", side_class(sig.recommended_side)]}>
                    <%= sig.recommended_side %>
                  </span>
                </td>
                <td class={"py-2 px-3 text-right font-semibold #{edge_color(sig.edge)}"}>
                  <%= format_edge(sig.edge) %>
                </td>
                <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400"><%= format_pct(sig.model_probability) %></td>
                <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= format_price(sig.market_price) %></td>
                <td class="py-2 pl-3">
                  <span class={["text-xs px-1.5 py-0.5 rounded-full", alert_class(sig.alert_level)]}>
                    <%= sig.alert_level || "signal" %>
                  </span>
                </td>
                <td class="py-2 pl-3">
                  <span class={["text-xs px-1.5 py-0.5 rounded", confidence_class(sig.confidence)]}>
                    <%= sig.confidence || "-" %>
                  </span>
                </td>
                <td class="py-2 pl-3 text-right">
                  <a
                    :if={signal_url(sig)}
                    href={signal_url(sig)}
                    target="_blank"
                    class="text-xs text-blue-500 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300 hover:underline"
                  >
                    Open
                  </a>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Active Markets -->
      <div :if={@station_clusters != []} class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <h3 class="text-sm font-semibold text-zinc-700 dark:text-zinc-300 mb-4">Active Markets</h3>
        <div class="space-y-3">
          <div :for={sc <- @station_clusters} class="rounded-md border border-zinc-100 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 p-3">
            <h4 class="text-sm font-semibold text-zinc-900 dark:text-zinc-100 mb-2"><%= sc.station.code %> — <%= sc.station.city %></h4>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
              <div :for={cluster <- sc.clusters} class="rounded border border-zinc-200 dark:border-zinc-600 bg-white dark:bg-zinc-900 p-2">
                <div class="flex items-center justify-between mb-1">
                  <span class="text-xs font-medium text-zinc-700 dark:text-zinc-300">
                    <%= Calendar.strftime(cluster.target_date, "%b %d") %>
                  </span>
                  <span class="text-xs text-zinc-400">
                    <%= Date.diff(cluster.target_date, Date.utc_today()) %>d
                  </span>
                </div>
                <div :if={cluster.outcomes} class="text-xs text-zinc-500 dark:text-zinc-400">
                  <%= for o <- top_outcomes(cluster.outcomes, 3) do %>
                    <span class="mr-2"><%= o["outcome_label"] %>: $<%= fmt_outcome_price(o["yes_price"]) %></span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Model Accuracy by Station -->
      <div :if={@station_stats != []} class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <h3 class="text-sm font-semibold text-zinc-700 dark:text-zinc-300 mb-4">Model Accuracy by Station</h3>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-zinc-200 dark:border-zinc-700 text-xs text-zinc-500 dark:text-zinc-400">
                <th class="text-left py-2 pr-4">Station</th>
                <th class="text-right py-2 px-3">Events</th>
                <th class="text-right py-2 px-3">Hit Rate</th>
                <th class="text-right py-2 px-3">MAE</th>
                <th class="text-right py-2 px-3">Mean Error</th>
                <th class="text-left py-2 pl-3">Best Model</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={stat <- @station_stats} class="border-b border-zinc-100 dark:border-zinc-800">
                <td class="py-2 pr-4 font-mono font-semibold text-zinc-900 dark:text-zinc-100"><%= stat.station_code %></td>
                <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400"><%= stat.count %></td>
                <td class="py-2 px-3 text-right">
                  <span class={if stat.hit_rate >= 0.5, do: "text-green-600", else: "text-red-600"}>
                    <%= Float.round(stat.hit_rate * 100, 1) %>%
                  </span>
                </td>
                <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400"><%= Float.round(stat.mae, 1) %>°</td>
                <td class="py-2 px-3 text-right">
                  <span class={if stat.mean_error >= 0, do: "text-orange-600", else: "text-blue-600"}>
                    <%= if stat.mean_error >= 0, do: "+", else: "" %><%= Float.round(stat.mean_error, 1) %>°
                  </span>
                </td>
                <td class="py-2 pl-3 text-zinc-600 dark:text-zinc-400"><%= best_model(stat) %></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Recent Closed Trades -->
      <div :if={@recent_trades != []} class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <h3 class="text-sm font-semibold text-zinc-700 dark:text-zinc-300 mb-4">Recent Closed Trades</h3>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-zinc-200 dark:border-zinc-700 text-xs text-zinc-500 dark:text-zinc-400">
                <th class="text-left py-2 pr-3">Station</th>
                <th class="text-left py-2 px-3">Outcome</th>
                <th class="text-right py-2 px-3">Avg Price</th>
                <th class="text-right py-2 px-3">Cost</th>
                <th class="text-right py-2 px-3">P&L</th>
                <th class="text-left py-2 pl-3">Status</th>
                <th class="text-left py-2 pl-3">Closed</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={pos <- @recent_trades} class="border-b border-zinc-100 dark:border-zinc-800">
                <td class="py-2 pr-3 font-mono font-semibold text-zinc-900 dark:text-zinc-100"><%= pos.station_code %></td>
                <td class="py-2 px-3 text-zinc-600 dark:text-zinc-400"><%= pos.outcome_label %></td>
                <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= format_price(pos.avg_buy_price) %></td>
                <td class="py-2 px-3 text-right text-zinc-600 dark:text-zinc-400">$<%= format_price(pos.total_cost_usdc) %></td>
                <td class={"py-2 px-3 text-right font-semibold #{pnl_color(pos.realized_pnl)}"}>
                  <%= format_pnl(pos.realized_pnl) %>
                </td>
                <td class="py-2 pl-3">
                  <span class={["text-xs px-1.5 py-0.5 rounded-full", status_class(pos.status)]}>
                    <%= status_label(pos.status) %>
                  </span>
                </td>
                <td class="py-2 pl-3 text-xs text-zinc-400">
                  <%= if pos.closed_at, do: Calendar.strftime(pos.closed_at, "%b %d %H:%M"), else: "-" %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # --- Components ---

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :color, :string, default: nil

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
      <p class="text-xs text-zinc-400"><%= @label %></p>
      <p class={"text-xl font-bold #{@color || "text-zinc-900 dark:text-zinc-100"}"}><%= @value %></p>
    </div>
    """
  end

  attr :data, :list, required: true

  defp pnl_chart(assigns) do
    data = assigns.data

    if data == [] do
      ~H"""
      <div class="h-48 flex items-center justify-center text-zinc-400 text-sm">
        No P&L data yet. Chart will appear after positions are closed.
      </div>
      """
    else
      values = Enum.map(data, & &1.cumulative)
      min_val = Enum.min(values)
      max_val = Enum.max(values)
      range = max(max_val - min_val, 0.01)
      padding = range * 0.1

      chart_min = min_val - padding
      chart_max = max_val + padding
      chart_range = chart_max - chart_min

      width = 800
      height = 200
      point_count = length(data)

      points =
        data
        |> Enum.with_index()
        |> Enum.map(fn {d, i} ->
          x = if point_count > 1, do: i / (point_count - 1) * width, else: width / 2
          y = height - (d.cumulative - chart_min) / chart_range * height
          {x, y}
        end)

      zero_y = height - (0.0 - chart_min) / chart_range * height

      polyline_points =
        points
        |> Enum.map(fn {x, y} -> "#{Float.round(x, 1)},#{Float.round(y, 1)}" end)
        |> Enum.join(" ")

      area_points =
        "#{Float.round(elem(hd(points), 0), 1)},#{Float.round(zero_y, 1)} " <>
          polyline_points <>
          " #{Float.round(elem(List.last(points), 0), 1)},#{Float.round(zero_y, 1)}"

      last_value = List.last(values)
      line_color = if last_value >= 0, do: "#16a34a", else: "#dc2626"
      fill_color = if last_value >= 0, do: "#16a34a20", else: "#dc262620"

      assigns =
        assigns
        |> assign(:width, width)
        |> assign(:height, height)
        |> assign(:polyline_points, polyline_points)
        |> assign(:area_points, area_points)
        |> assign(:zero_y, zero_y)
        |> assign(:line_color, line_color)
        |> assign(:fill_color, fill_color)
        |> assign(:chart_min, chart_min)
        |> assign(:chart_max, chart_max)
        |> assign(:labels, build_labels(data))

      ~H"""
      <div class="w-full overflow-hidden">
        <svg viewBox={"0 -20 #{@width} #{@height + 40}"} class="w-full h-48">
          <line x1="0" y1={@zero_y} x2={@width} y2={@zero_y} stroke="#a1a1aa" stroke-width="0.5" stroke-dasharray="4" />
          <polygon points={@area_points} fill={@fill_color} />
          <polyline points={@polyline_points} fill="none" stroke={@line_color} stroke-width="2" />
          <text x="2" y="-5" font-size="10" fill="#a1a1aa">$<%= format_pnl(@chart_max) %></text>
          <text x="2" y={@height + 12} font-size="10" fill="#a1a1aa">$<%= format_pnl(@chart_min) %></text>
          <text :for={{label, x} <- @labels} x={x} y={@height + 25} font-size="9" fill="#a1a1aa" text-anchor="middle">
            <%= label %>
          </text>
        </svg>
      </div>
      """
    end
  end

  # --- Helpers ---

  defp build_cumulative(daily_pnl) do
    daily_pnl
    |> Enum.reduce({0.0, []}, fn day, {running, acc} ->
      cumulative = running + (day.pnl || 0.0)
      {cumulative, [%{date: day.date, pnl: day.pnl, cumulative: cumulative, count: day.count} | acc]}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp build_labels(data) do
    count = length(data)
    step = max(div(count, 5), 1)

    data
    |> Enum.with_index()
    |> Enum.filter(fn {_, i} -> rem(i, step) == 0 or i == count - 1 end)
    |> Enum.map(fn {d, i} ->
      x = if count > 1, do: i / (count - 1) * 800, else: 400
      {Calendar.strftime(d.date, "%b %d"), x}
    end)
  end

  defp top_outcomes(outcomes, n) when is_list(outcomes) do
    outcomes
    |> Enum.sort_by(fn o ->
      case o["yes_price"] do
        p when is_number(p) -> -p
        p when is_binary(p) -> case Float.parse(p) do {v, _} -> -v; _ -> 0 end
        _ -> 0
      end
    end)
    |> Enum.take(n)
  end
  defp top_outcomes(_, _), do: []

  defp format_pnl(nil), do: "0.00"
  defp format_pnl(value) when is_number(value) do
    sign = if value >= 0, do: "+", else: "-"
    "#{sign}#{:erlang.float_to_binary(abs(value * 1.0), decimals: 2)}"
  end

  defp format_price(nil), do: "0.00"
  defp format_price(val) when is_number(val), do: :erlang.float_to_binary(val * 1.0, decimals: 2)

  defp format_pct(nil), do: "-"
  defp format_pct(val) when is_number(val), do: "#{:erlang.float_to_binary(val * 100, decimals: 1)}%"

  defp format_edge(nil), do: "-"
  defp format_edge(val) when is_number(val) do
    sign = if val >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(val * 100, decimals: 1)}%"
  end

  defp fmt_sidecar(nil), do: "—"
  defp fmt_sidecar(val) when is_number(val), do: :erlang.float_to_binary(val * 1.0, decimals: 2)
  defp fmt_sidecar(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> :erlang.float_to_binary(f, decimals: 2)
      :error -> val
    end
  end

  defp fmt_outcome_price(nil), do: "?"
  defp fmt_outcome_price(val) when is_number(val), do: :erlang.float_to_binary(val * 1.0, decimals: 2)
  defp fmt_outcome_price(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> :erlang.float_to_binary(f, decimals: 2)
      :error -> val
    end
  end

  defp parse_num(nil), do: 0
  defp parse_num(val) when is_number(val), do: val
  defp parse_num(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0
    end
  end

  defp pnl_color(nil), do: "text-zinc-500"
  defp pnl_color(val) when is_number(val) and val > 0, do: "text-green-600"
  defp pnl_color(val) when is_number(val) and val < 0, do: "text-red-600"
  defp pnl_color(_), do: "text-zinc-500 dark:text-zinc-400"

  defp edge_color(nil), do: "text-zinc-400"
  defp edge_color(val) when is_number(val) and val > 0.10, do: "text-green-600"
  defp edge_color(val) when is_number(val) and val > 0, do: "text-green-500"
  defp edge_color(_), do: "text-zinc-400"

  defp side_class("YES"), do: "bg-green-600 text-white"
  defp side_class("NO"), do: "bg-red-600 text-white"
  defp side_class(_), do: "bg-zinc-200 text-zinc-600"

  defp alert_class("extreme"), do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
  defp alert_class("strong"), do: "bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400"
  defp alert_class("opportunity"), do: "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400"
  defp alert_class("safe_no"), do: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
  defp alert_class(_), do: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"

  defp confidence_class("confirmed"), do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400"
  defp confidence_class("high"), do: "bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-400"
  defp confidence_class("forecast"), do: "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-500"
  defp confidence_class(_), do: "bg-zinc-50 text-zinc-400 dark:bg-zinc-800 dark:text-zinc-500"

  defp signal_url(%{market_cluster: %{event_slug: slug}}) when is_binary(slug) and slug != "" do
    "https://polymarket.com/event/#{slug}"
  end
  defp signal_url(_), do: nil

  defp best_model(%{model_stats: model_stats}) when map_size(model_stats) > 0 do
    {model, _} = Enum.min_by(model_stats, fn {_m, s} -> s.mae end)
    model
  end
  defp best_model(_), do: "-"

  defp status_class("resolved_win"), do: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
  defp status_class("resolved_loss"), do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
  defp status_class("sold"), do: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"
  defp status_class("closed"), do: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"
  defp status_class(_), do: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"

  defp status_label("resolved_win"), do: "Win"
  defp status_label("resolved_loss"), do: "Loss"
  defp status_label("sold"), do: "Sold"
  defp status_label("closed"), do: "Closed"
  defp status_label(s), do: s
end
