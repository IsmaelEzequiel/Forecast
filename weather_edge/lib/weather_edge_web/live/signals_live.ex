defmodule WeatherEdgeWeb.SignalsLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.PubSubHelper
  alias WeatherEdge.Signals.Queries
  alias WeatherEdge.Signals.DetailData
  alias WeatherEdge.Signals.GroupedView
  alias WeatherEdge.Signals.HeatmapData
  alias WeatherEdge.Signals.Performance
  alias WeatherEdge.Stations
  alias WeatherEdge.Markets
  alias WeatherEdge.Trading.OrderManager

  import Ecto.Query
  import WeatherEdgeWeb.Components.HeaderComponent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSubHelper.subscribe(PubSubHelper.signals_new())
      PubSubHelper.subscribe(PubSubHelper.portfolio_balance_update())
      PubSubHelper.subscribe(PubSubHelper.portfolio_position_update())
    end

    wallet_address = Application.get_env(:weather_edge, :polymarket)[:wallet_address]
    cached_balance = :persistent_term.get(:sidecar_balance, nil)

    filters = default_filters()

    station_codes =
      if connected?(socket) do
        Stations.list_stations() |> Enum.map(& &1.code) |> Enum.sort()
      else
        []
      end

    {signals, total_count} =
      if connected?(socket) do
        {Queries.list_filtered_signals(filters), Queries.count_filtered_signals(filters)}
      else
        {[], 0}
      end

    {:ok,
     assign(socket,
       filters: filters,
       signals: signals,
       total_count: total_count,
       selected: MapSet.new(),
       view_mode: :table,
       detail_signal_id: nil,
       detail_data: nil,
       detail_loading: false,
       detail_buy_amount: nil,
       balance: cached_balance,
       wallet_address: wallet_address,
       station_codes: station_codes,
       offset: 0,
       buying: false,
       buy_progress: nil,
       performance_expanded: false,
       performance_data: nil,
       highlighted: MapSet.new()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 pb-24">
      <.dashboard_header balance={@balance} wallet_address={@wallet_address} />

      <div class="sticky top-0 z-30 rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4 space-y-3">
        <div class="flex items-center justify-between">
          <.filter_bar filters={@filters} station_codes={@station_codes} total_count={@total_count} signals_count={length(@signals)} />
          <div class="flex items-center gap-2">
            <button
              phx-click="export_signals"
              class="px-3 py-1.5 text-xs font-medium rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400 hover:bg-zinc-50 dark:hover:bg-zinc-700 transition-colors"
            >
              Export JSON
            </button>
            <.view_mode_toggle view_mode={@view_mode} />
          </div>
        </div>
      </div>

      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900">
        <%= case @view_mode do %>
          <% :table -> %>
            <.signals_table signals={@signals} selected={@selected} total_count={@total_count} highlighted={@highlighted} />
          <% :grouped -> %>
            <.grouped_view signals={@signals} />
          <% :heatmap -> %>
            <.heatmap_view signals={@signals} />
          <% _other -> %>
            <div class="p-4">
              <p class="text-sm text-zinc-500 dark:text-zinc-400">
                <%= @view_mode %> view | Showing <%= length(@signals) %> of <%= @total_count %> signals
              </p>
            </div>
        <% end %>
      </div>

      <.performance_tracker
        performance_expanded={@performance_expanded}
        performance_data={@performance_data}
      />

      <.quick_actions_bar
        selected={@selected}
        signals={@signals}
        balance={@balance}
        buying={@buying}
        buy_progress={@buy_progress}
      />

      <.detail_panel
        :if={@detail_signal_id != nil}
        detail_data={@detail_data}
        detail_loading={@detail_loading}
        detail_buy_amount={@detail_buy_amount}
        buying={@buying}
      />

      <div
        :if={@detail_signal_id != nil}
        phx-click="close_detail"
        class="fixed inset-0 z-40 bg-black/20"
      />
    </div>
    """
  end

  defp performance_tracker(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 mb-16">
      <button
        phx-click="toggle_performance"
        class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-zinc-800/50 transition-colors"
      >
        <span>Performance Tracker</span>
        <span class="text-xs text-zinc-400"><%= if @performance_expanded, do: "▲", else: "▼" %></span>
      </button>

      <div :if={@performance_expanded && @performance_data} class="border-t border-zinc-200 dark:border-zinc-700 p-4 space-y-6">
        <.performance_summary stats={@performance_data} />
        <.accuracy_by_level_table levels={@performance_data.accuracy_by_level} />
        <.accuracy_by_station_table stations={@performance_data.accuracy_by_station} />
        <.signal_history_table history={@performance_data.signal_history} />
      </div>

      <div :if={@performance_expanded && !@performance_data} class="border-t border-zinc-200 dark:border-zinc-700 p-4">
        <p class="text-sm text-zinc-400">Loading performance data...</p>
      </div>
    </div>
    """
  end

  defp performance_summary(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
      <div class="text-center">
        <div class="text-2xl font-bold text-zinc-900 dark:text-zinc-100">
          <%= format_pct(@stats.accuracy) %>
        </div>
        <div class="text-xs text-zinc-500 dark:text-zinc-400">Accuracy</div>
      </div>
      <div class="text-center">
        <div class="text-2xl font-bold text-zinc-900 dark:text-zinc-100">
          <%= format_edge(@stats.avg_edge) %>
        </div>
        <div class="text-xs text-zinc-500 dark:text-zinc-400">Avg Edge</div>
      </div>
      <div class="text-center">
        <div class={"text-2xl font-bold #{pnl_color(@stats.total_pnl)}"}>
          $<%= format_price(@stats.total_pnl) %>
        </div>
        <div class="text-xs text-zinc-500 dark:text-zinc-400">Total P&L</div>
      </div>
      <div class="text-center">
        <div class="text-2xl font-bold text-zinc-900 dark:text-zinc-100">
          <%= @stats.total_signals %>
        </div>
        <div class="text-xs text-zinc-500 dark:text-zinc-400">Signals Tracked</div>
      </div>
    </div>
    """
  end

  defp accuracy_by_level_table(assigns) do
    levels = assigns.levels |> Enum.sort_by(fn {_k, v} -> -v.count end)
    assigns = assign(assigns, :sorted_levels, levels)

    ~H"""
    <div>
      <h4 class="text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wide mb-2">By Alert Level</h4>
      <table class="w-full text-xs">
        <thead>
          <tr class="border-b border-zinc-200 dark:border-zinc-700 text-left text-zinc-500 dark:text-zinc-400">
            <th class="px-3 py-1.5">Level</th>
            <th class="px-3 py-1.5">Count</th>
            <th class="px-3 py-1.5">Accuracy</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{level, data} <- @sorted_levels} class="border-b border-zinc-100 dark:border-zinc-800">
            <td class="px-3 py-1.5">
              <span class={"inline-block px-2 py-0.5 rounded text-xs font-medium #{alert_class(level)}"}>
                <%= format_alert(level) %>
              </span>
            </td>
            <td class="px-3 py-1.5 text-zinc-700 dark:text-zinc-300"><%= data.count %></td>
            <td class="px-3 py-1.5 font-medium text-zinc-900 dark:text-zinc-100"><%= format_pct(data.accuracy) %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp accuracy_by_station_table(assigns) do
    stations = assigns.stations |> Enum.sort_by(fn {code, _} -> code end)
    assigns = assign(assigns, :sorted_stations, stations)

    ~H"""
    <div>
      <h4 class="text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wide mb-2">By Station</h4>
      <table class="w-full text-xs">
        <thead>
          <tr class="border-b border-zinc-200 dark:border-zinc-700 text-left text-zinc-500 dark:text-zinc-400">
            <th class="px-3 py-1.5">Station</th>
            <th class="px-3 py-1.5">Count</th>
            <th class="px-3 py-1.5">Accuracy</th>
            <th class="px-3 py-1.5">P&L</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{code, data} <- @sorted_stations} class="border-b border-zinc-100 dark:border-zinc-800">
            <td class="px-3 py-1.5 font-mono text-zinc-700 dark:text-zinc-300"><%= code %></td>
            <td class="px-3 py-1.5 text-zinc-700 dark:text-zinc-300"><%= Map.get(data, :count, 0) %></td>
            <td class="px-3 py-1.5 font-medium text-zinc-900 dark:text-zinc-100"><%= format_pct(Map.get(data, :accuracy, 0.0)) %></td>
            <td class={"px-3 py-1.5 font-medium #{pnl_color(Map.get(data, :pnl, 0.0))}"}>$<%= format_price(Map.get(data, :pnl, 0.0)) %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp signal_history_table(assigns) do
    ~H"""
    <div>
      <h4 class="text-xs font-medium text-zinc-500 dark:text-zinc-400 uppercase tracking-wide mb-2">Signal History</h4>
      <div class="overflow-x-auto">
        <table class="w-full text-xs">
          <thead>
            <tr class="border-b border-zinc-200 dark:border-zinc-700 text-left text-zinc-500 dark:text-zinc-400">
              <th class="px-3 py-1.5">Date</th>
              <th class="px-3 py-1.5">Station</th>
              <th class="px-3 py-1.5">Temp</th>
              <th class="px-3 py-1.5">Edge</th>
              <th class="px-3 py-1.5">Result</th>
              <th class="px-3 py-1.5">P&L</th>
              <th class="px-3 py-1.5">Correct</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={entry <- @history} class="border-b border-zinc-100 dark:border-zinc-800">
              <td class="px-3 py-1.5 text-zinc-700 dark:text-zinc-300"><%= entry.date %></td>
              <td class="px-3 py-1.5 font-mono text-zinc-700 dark:text-zinc-300"><%= entry.station %></td>
              <td class="px-3 py-1.5 text-zinc-700 dark:text-zinc-300"><%= entry.temp || "-" %></td>
              <td class={"px-3 py-1.5 font-medium #{edge_color(entry.edge)}"}><%= format_edge(entry.edge) %></td>
              <td class="px-3 py-1.5">
                <span class={"inline-block px-2 py-0.5 rounded text-xs font-medium #{result_class(entry.result)}"}>
                  <%= String.upcase(entry.result) %>
                </span>
              </td>
              <td class={"px-3 py-1.5 font-medium #{pnl_color(entry.pnl)}"}>
                <%= if entry.pnl, do: "$#{format_price(entry.pnl)}", else: "-" %>
              </td>
              <td class="px-3 py-1.5">
                <%= if entry.correct, do: "✓", else: "✗" %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp quick_actions_bar(assigns) do
    selected_signals = Enum.filter(assigns.signals, fn row -> MapSet.member?(assigns.selected, row.signal.id) end)
    buy_amount = assigns[:detail_buy_amount]
    estimated_cost = Enum.reduce(selected_signals, 0.0, fn row, acc -> acc + (buy_amount || row.station.buy_amount_usdc || 1.0) end)
    selected_count = MapSet.size(assigns.selected)

    assigns =
      assigns
      |> assign(:selected_count, selected_count)
      |> assign(:estimated_cost, estimated_cost)

    ~H"""
    <div class="fixed bottom-0 left-0 right-0 z-40 border-t border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 px-6 py-3 shadow-lg">
      <div class="flex items-center justify-between max-w-7xl mx-auto">
        <div class="flex items-center gap-4 text-sm">
          <span class="text-zinc-500 dark:text-zinc-400">
            Balance: <span class="font-medium text-zinc-900 dark:text-zinc-100">$<%= format_price(@balance || 0) %></span>
          </span>
          <span class="text-zinc-500 dark:text-zinc-400">
            Selected: <span class="font-medium text-zinc-900 dark:text-zinc-100"><%= @selected_count %></span>
          </span>
          <span :if={@selected_count > 0} class="text-zinc-500 dark:text-zinc-400">
            Est. Cost: <span class="font-medium text-zinc-900 dark:text-zinc-100">$<%= format_price(@estimated_cost) %></span>
          </span>
        </div>
        <div class="flex items-center gap-3">
          <span :if={@buying && @buy_progress} class="text-sm text-blue-600 dark:text-blue-400 font-medium">
            <%= @buy_progress %>
          </span>
          <button
            phx-click="buy_selected"
            disabled={@selected_count == 0 || @buying}
            class={[
              "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
              if(@selected_count > 0 && !@buying,
                do: "bg-green-600 hover:bg-green-700 text-white",
                else: "bg-zinc-200 dark:bg-zinc-700 text-zinc-400 dark:text-zinc-500 cursor-not-allowed"
              )
            ]}
          >
            <%= if @buying, do: "Buying...", else: "BUY ALL #{@selected_count}" %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp signals_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-xs">
        <thead>
          <tr class="border-b border-zinc-200 dark:border-zinc-700 text-left text-zinc-500 dark:text-zinc-400">
            <th class="px-3 py-2 w-8"></th>
            <th class="px-3 py-2">Time</th>
            <th class="px-3 py-2">Station</th>
            <th class="px-3 py-2">Temp</th>
            <th class="px-3 py-2">Resolves</th>
            <th class="px-3 py-2">Action</th>
            <th class="px-3 py-2">Alert</th>
            <th class="px-3 py-2">Confidence</th>
            <th class="px-3 py-2">Market</th>
            <th class="px-3 py-2">Model</th>
            <th class="px-3 py-2">Edge</th>
            <th class="px-3 py-2">Volume</th>
            <th class="px-3 py-2">Trend</th>
            <th class="px-3 py-2">Pos?</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={row <- @signals}
            phx-click="open_detail"
            phx-value-id={row.signal.id}
            class={[
              "border-b border-zinc-100 dark:border-zinc-800 hover:bg-zinc-50 dark:hover:bg-zinc-800/50 cursor-pointer transition-colors",
              MapSet.member?(@highlighted, row.signal.id) && "bg-green-50 dark:bg-green-900/20 animate-pulse"
            ]}
          >
            <td class="px-3 py-2">
              <input
                type="checkbox"
                checked={MapSet.member?(@selected, row.signal.id)}
                phx-click="toggle_select"
                phx-value-id={row.signal.id}
                class="rounded border-zinc-300 dark:border-zinc-600 text-blue-600"
              />
            </td>
            <td class="px-3 py-2 text-zinc-600 dark:text-zinc-400 whitespace-nowrap">
              <%= format_time(row.signal.computed_at) %>
            </td>
            <td class="px-3 py-2">
              <button
                phx-click="filter_station"
                phx-value-code={row.signal.station_code}
                class="font-medium text-blue-600 dark:text-blue-400 hover:underline"
              >
                <%= row.signal.station_code %>
              </button>
            </td>
            <td class="px-3 py-2 text-zinc-700 dark:text-zinc-300">
              <%= row.signal.outcome_label %>
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <.resolves_cell hours={row.hours_to_resolution} target_date={row.cluster.target_date} />
            </td>
            <td class="px-3 py-2">
              <.action_badge side={row.signal.recommended_side} position={row.position} />
            </td>
            <td class="px-3 py-2">
              <span class={["px-1.5 py-0.5 rounded text-[10px] font-medium", alert_class(row.signal.alert_level)]}>
                <%= format_alert(row.signal.alert_level) %>
              </span>
            </td>
            <td class="px-3 py-2">
              <span class={["px-1.5 py-0.5 rounded text-[10px] font-medium", confidence_class(row.signal.confidence)]}>
                <%= row.signal.confidence || "-" %>
              </span>
            </td>
            <td class="px-3 py-2 text-zinc-700 dark:text-zinc-300 whitespace-nowrap">
              $<%= format_price(row.signal.market_price) %>
              <span
                :if={stale_signal?(row)}
                title="Price may be stale (>10% deviation from current market)"
                class="ml-1 text-amber-500 dark:text-amber-400"
              >⚠</span>
            </td>
            <td class="px-3 py-2 text-zinc-700 dark:text-zinc-300">
              <%= format_pct(row.signal.model_probability) %>
            </td>
            <td class="px-3 py-2">
              <span class={["font-bold", edge_color(row.signal.edge)]}>
                <%= format_edge(row.signal.edge) %>
              </span>
            </td>
            <td class="px-3 py-2 text-zinc-500 dark:text-zinc-400">
              <%= format_volume(row.cluster.outcomes, row.signal.outcome_label) %>
            </td>
            <td class="px-3 py-2 whitespace-nowrap">
              <.trend_cell cluster_id={row.cluster.id} outcome_label={row.signal.outcome_label} />
            </td>
            <td class="px-3 py-2 text-zinc-600 dark:text-zinc-400">
              <%= if row.position, do: format_tokens(row.position.tokens), else: "-" %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div :if={length(@signals) < @total_count} class="p-3 text-center border-t border-zinc-200 dark:border-zinc-700">
      <button
        phx-click="load_more"
        class="text-xs text-blue-600 dark:text-blue-400 hover:underline font-medium"
      >
        Show more (<%= length(@signals) %> of <%= @total_count %>)
      </button>
    </div>
    """
  end

  defp grouped_view(assigns) do
    groups = GroupedView.group_signals_by_event(assigns.signals)
    assigns = assign(assigns, :groups, groups)

    ~H"""
    <div class="divide-y divide-zinc-200 dark:divide-zinc-700">
      <div :if={@groups == []} class="p-6 text-center text-sm text-zinc-500 dark:text-zinc-400">
        No signals to group
      </div>
      <.grouped_card :for={group <- @groups} group={group} />
    </div>
    """
  end

  defp grouped_card(assigns) do
    health_deviation = abs(assigns.group.cluster_health - 1.0)

    assigns =
      assigns
      |> assign(:health_deviation, health_deviation)

    ~H"""
    <details class="group" open>
      <summary class="flex items-center justify-between px-4 py-3 cursor-pointer hover:bg-zinc-50 dark:hover:bg-zinc-800/50 transition-colors">
        <div class="flex items-center gap-3">
          <span class="font-bold text-sm text-zinc-900 dark:text-zinc-100"><%= @group.station_code %></span>
          <span class="text-xs text-zinc-500 dark:text-zinc-400"><%= @group.station.city %></span>
          <span class="text-xs text-zinc-500 dark:text-zinc-400"><%= @group.cluster.target_date %></span>
          <span class={["text-xs font-medium", if(@group.hours_to_resolution && @group.hours_to_resolution < 6, do: "text-red-600 dark:text-red-400", else: "text-zinc-600 dark:text-zinc-400")]}>
            <%= if @group.hours_to_resolution, do: "#{@group.hours_to_resolution}h", else: "-" %>
          </span>
        </div>
        <div class="flex items-center gap-3 text-xs">
          <span class="text-zinc-500 dark:text-zinc-400"><%= @group.signal_count %> signals</span>
          <svg class="w-4 h-4 text-zinc-400 transition-transform group-open:rotate-180" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
          </svg>
        </div>
      </summary>

      <div class="px-4 pb-4 space-y-3">
        <div class="flex items-center gap-2 text-xs">
          <span class="text-zinc-500 dark:text-zinc-400">Cluster Health:</span>
          <span class="font-medium text-zinc-700 dark:text-zinc-300">
            &Sigma; YES = <%= :erlang.float_to_binary(@group.cluster_health * 1.0, decimals: 2) %>
          </span>
          <span :if={@health_deviation > 0.05} class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400">
            Deviation &gt; 5%
          </span>
        </div>

        <div class="rounded-lg border border-green-200 dark:border-green-800 bg-green-50 dark:bg-green-900/20 p-3 space-y-2">
          <div class="text-[10px] font-semibold text-green-700 dark:text-green-400 uppercase tracking-wider">Best Play</div>
          <.grouped_signal_row row={@group.best_play} highlight={true} />
          <div class="text-xs text-zinc-500 dark:text-zinc-400">
            Payout: $<%= format_payout(@group.best_play) %> | Return: <%= format_return_pct(@group.best_play) %>
          </div>
        </div>

        <div :if={@group.hedge_options != []} class="rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/20 p-3 space-y-2">
          <div class="text-[10px] font-semibold text-blue-700 dark:text-blue-400 uppercase tracking-wider">Hedge Options</div>
          <.grouped_signal_row :for={row <- @group.hedge_options} row={row} highlight={false} />
        </div>

        <div :if={@group.other_signals != []} class="rounded-lg border border-zinc-200 dark:border-zinc-700 p-3 space-y-2">
          <div class="text-[10px] font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Other</div>
          <.grouped_signal_row :for={row <- @group.other_signals} row={row} highlight={false} />
        </div>

        <div class="flex gap-2 pt-1">
          <button
            phx-click="buy_best"
            phx-value-signal-id={@group.best_play.signal.id}
            class="px-3 py-1.5 rounded-lg text-xs font-medium bg-green-600 hover:bg-green-700 text-white transition-colors"
          >
            BUY BEST
          </button>
          <button
            :if={@group.hedge_options != []}
            phx-click="buy_best_hedge"
            phx-value-best-id={@group.best_play.signal.id}
            phx-value-hedge-id={hd(@group.hedge_options).signal.id}
            class="px-3 py-1.5 rounded-lg text-xs font-medium bg-blue-600 hover:bg-blue-700 text-white transition-colors"
          >
            BUY BEST + HEDGE
          </button>
          <button
            phx-click="open_detail"
            phx-value-id={@group.best_play.signal.id}
            class="px-3 py-1.5 rounded-lg text-xs font-medium border border-zinc-300 dark:border-zinc-600 text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-zinc-800 transition-colors"
          >
            VIEW FULL CLUSTER
          </button>
        </div>
      </div>
    </details>
    """
  end

  defp grouped_signal_row(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-between text-xs py-1",
      if(@highlight, do: "font-medium", else: "")
    ]}>
      <div class="flex items-center gap-2">
        <span class="text-zinc-700 dark:text-zinc-300"><%= @row.signal.outcome_label %></span>
        <.action_badge side={@row.signal.recommended_side} position={@row.position} />
        <span class={["px-1.5 py-0.5 rounded text-[10px] font-medium", alert_class(@row.signal.alert_level)]}>
          <%= format_alert(@row.signal.alert_level) %>
        </span>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-zinc-500 dark:text-zinc-400">$<%= format_price(@row.signal.market_price) %></span>
        <span class="text-zinc-500 dark:text-zinc-400"><%= format_pct(@row.signal.model_probability) %></span>
        <span class={["font-bold", edge_color(@row.signal.edge)]}>
          <%= format_edge(@row.signal.edge) %>
        </span>
      </div>
    </div>
    """
  end

  defp format_payout(row) do
    amount = row.station.buy_amount_usdc || 5.0
    market_price = row.signal.market_price || 0.01
    tokens = if market_price > 0, do: amount / market_price, else: 0.0
    payout = tokens * 1.0 - amount
    :erlang.float_to_binary(payout, decimals: 2)
  end

  defp heatmap_view(assigns) do
    heatmap = HeatmapData.build_heatmap(assigns.signals)
    assigns = assign(assigns, :heatmap, heatmap)

    ~H"""
    <div class="overflow-x-auto p-4">
      <div :if={@heatmap.stations == []} class="text-center text-sm text-zinc-500 dark:text-zinc-400 py-6">
        No signals available for heatmap
      </div>
      <table :if={@heatmap.stations != []} class="w-full text-xs">
        <thead>
          <tr class="border-b border-zinc-200 dark:border-zinc-700 text-left text-zinc-500 dark:text-zinc-400">
            <th class="px-3 py-2 font-medium">Station</th>
            <th :for={d <- @heatmap.dates} class="px-3 py-2 font-medium text-center"><%= d.label %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={station <- @heatmap.stations} class="border-b border-zinc-100 dark:border-zinc-800">
            <td class="px-3 py-2">
              <span class="font-medium text-zinc-900 dark:text-zinc-100"><%= station.code %></span>
              <span :if={station.city} class="ml-1 text-zinc-400 dark:text-zinc-500"><%= station.city %></span>
            </td>
            <td
              :for={{cell, idx} <- Enum.with_index(station.cells)}
              class="px-3 py-2 text-center"
            >
              <div
                :if={cell.has_event}
                phx-click="heatmap_click"
                phx-value-station={station.code}
                phx-value-date={Enum.at(@heatmap.dates, idx).date |> Date.to_iso8601()}
                class={[
                  "relative rounded-lg px-3 py-2 cursor-pointer transition-colors font-bold",
                  heatmap_cell_color(cell.best_edge)
                ]}
              >
                <%= format_edge(cell.best_edge) %>
                <span :if={cell.has_position} class="absolute top-1 right-1 w-2 h-2 rounded-full bg-purple-500" />
              </div>
              <div
                :if={!cell.has_event}
                class="rounded-lg px-3 py-2 bg-zinc-100 dark:bg-zinc-800 text-zinc-300 dark:text-zinc-600"
              >
                -
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp heatmap_cell_color(nil), do: "bg-zinc-100 dark:bg-zinc-800 text-zinc-400 dark:text-zinc-500"
  defp heatmap_cell_color(edge) when edge < 8, do: "bg-zinc-200 dark:bg-zinc-700 text-zinc-600 dark:text-zinc-400"
  defp heatmap_cell_color(edge) when edge < 15, do: "bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400"
  defp heatmap_cell_color(edge) when edge < 25, do: "bg-green-300 dark:bg-green-800/50 text-green-800 dark:text-green-300"
  defp heatmap_cell_color(_edge), do: "bg-green-500 dark:bg-green-700 text-white"

  defp format_return_pct(row) do
    amount = row.station.buy_amount_usdc || 5.0
    market_price = row.signal.market_price || 0.01
    tokens = if market_price > 0, do: amount / market_price, else: 0.0
    payout = tokens * 1.0
    return_pct = if amount > 0, do: (payout - amount) / amount * 100, else: 0.0
    format_return(return_pct)
  end

  defp resolves_cell(assigns) do
    today = Date.utc_today()
    resolves_today = assigns.target_date == today

    assigns =
      assigns
      |> assign(:resolves_today, resolves_today)
      |> assign(:urgent, assigns.hours != nil and assigns.hours < 6)

    ~H"""
    <span class={[if(@urgent, do: "text-red-600 dark:text-red-400 font-medium", else: "text-zinc-600 dark:text-zinc-400")]}>
      <%= if @hours, do: "#{@hours}h", else: "-" %>
    </span>
    <span :if={@resolves_today} class="ml-1 px-1 py-0.5 bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 rounded text-[10px] font-medium">
      Today
    </span>
    """
  end

  defp action_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% @position != nil -> %>
        <span class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400">
          BOUGHT
        </span>
      <% @side == "YES" -> %>
        <span class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400">
          BUY YES
        </span>
      <% @side == "NO" -> %>
        <span class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400">
          BUY NO
        </span>
      <% true -> %>
        <span class="text-zinc-400">-</span>
    <% end %>
    """
  end

  defp trend_cell(assigns) do
    {direction, delta} = Markets.price_trend(assigns.cluster_id, assigns.outcome_label)
    assigns = assign(assigns, direction: direction, delta: delta)

    ~H"""
    <span class={trend_color(@direction)}>
      <%= trend_arrow(@direction) %> <%= format_trend_delta(@delta) %>
    </span>
    """
  end

  defp filter_bar(assigns) do
    active_count = count_active_filters(assigns.filters)
    assigns = assign(assigns, :active_count, active_count)

    ~H"""
    <form phx-change="update_filter" class="flex-1 space-y-3">
      <div class="flex flex-wrap gap-3 items-end">
        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Stations</label>
          <select
            name="stations"
            multiple
            class="block w-40 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option
              :for={code <- @station_codes}
              value={code}
              selected={code in @filters.stations}
            >
              <%= code %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Min Edge %</label>
          <input
            type="number"
            name="min_edge"
            value={@filters.min_edge}
            min="0"
            max="60"
            step="1"
            class="block w-20 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Resolution</label>
          <select
            name="resolution_date"
            class="block w-28 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option :for={{val, label} <- [{"all", "All"}, {"today", "Today"}, {"tomorrow", "Tomorrow"}, {"+2d", "+2d"}, {"+3d", "+3d"}]} value={val} selected={@filters.resolution_date == val}>
              <%= label %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Side</label>
          <select
            name="side"
            class="block w-20 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option :for={{val, label} <- [{"all", "All"}, {"YES", "YES"}, {"NO", "NO"}]} value={val} selected={@filters.side == val}>
              <%= label %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Max Price</label>
          <input
            type="number"
            name="max_price"
            value={@filters.max_price}
            min="0"
            max="1"
            step="0.01"
            placeholder="Any"
            class="block w-20 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Alert Level</label>
          <select
            name="alert_level"
            class="block w-28 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option
              :for={{val, label} <- [{"all", "All"}, {"extreme", "Extreme"}, {"strong", "Strong"}, {"opportunity", "Opportunity"}, {"safe_no", "Safe NO"}]}
              value={val}
              selected={@filters.alert_level == val}
            >
              <%= label %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Sort</label>
          <select
            name="sort_by"
            class="block w-36 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option
              :for={{val, label} <- [{"edge_desc", "Highest Edge"}, {"price_asc", "Lowest Price"}, {"model_prob_desc", "Highest Model Prob"}, {"time_to_resolution", "Soonest Resolution"}, {"newest", "Newest"}]}
              value={val}
              selected={@filters.sort_by == val}
            >
              <%= label %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Position</label>
          <select
            name="has_position"
            class="block w-32 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option :for={{val, label} <- [{"all", "All"}, {"with_position", "With Position"}, {"without_position", "Without Position"}]} value={val} selected={@filters.has_position == val}>
              <%= label %>
            </option>
          </select>
        </div>

        <label class="flex items-center gap-1.5 pb-0.5 cursor-pointer">
          <input
            type="checkbox"
            name="actionable_only"
            checked={@filters.actionable_only}
            phx-click="toggle_actionable"
            class="rounded border-zinc-300 dark:border-zinc-600 text-blue-600"
          />
          <span class="text-xs text-zinc-600 dark:text-zinc-400">Actionable Only</span>
        </label>
      </div>

      <div class="flex items-center gap-2 text-xs text-zinc-500 dark:text-zinc-400">
        <span>Active: <%= @active_count %> filters | Showing <%= @signals_count %> of <%= @total_count %> signals</span>
        <button
          :if={@active_count > 0}
          phx-click="clear_filters"
          class="text-blue-600 dark:text-blue-400 hover:underline"
        >
          Clear All
        </button>
      </div>
    </form>
    """
  end

  defp view_mode_toggle(assigns) do
    ~H"""
    <div class="flex items-center rounded-lg border border-zinc-200 dark:border-zinc-700 overflow-hidden">
      <button
        :for={{mode, label} <- [table: "Table", grouped: "Grouped", heatmap: "Heatmap"]}
        phx-click="set_view"
        phx-value-mode={mode}
        class={[
          "px-3 py-1.5 text-xs font-medium transition-colors",
          if(@view_mode == mode,
            do: "bg-blue-600 text-white",
            else: "bg-white dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400 hover:bg-zinc-50 dark:hover:bg-zinc-700"
          )
        ]}
      >
        <%= label %>
      </button>
    </div>
    """
  end

  defp detail_panel(assigns) do
    ~H"""
    <div class="fixed top-0 right-0 w-2/5 h-full z-50 bg-white dark:bg-zinc-900 border-l border-zinc-200 dark:border-zinc-700 shadow-xl overflow-y-auto transition-transform">
      <div class="sticky top-0 z-10 bg-white dark:bg-zinc-900 border-b border-zinc-200 dark:border-zinc-700 px-4 py-3 flex items-center justify-between">
        <h2 class="text-sm font-semibold text-zinc-900 dark:text-zinc-100">Signal Detail</h2>
        <button
          phx-click="close_detail"
          class="text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 text-lg leading-none"
        >
          &times;
        </button>
      </div>

      <%= if @detail_loading do %>
        <div class="flex items-center justify-center py-16">
          <div class="text-sm text-zinc-500 dark:text-zinc-400">Loading detail...</div>
        </div>
      <% else %>
        <%= if @detail_data do %>
          <div class="p-4 space-y-5">
            <.detail_header
              signal={@detail_data.signal}
              cluster={@detail_data.cluster}
              station={@detail_data.station}
            />

            <.distribution_chart_section
              distribution={@detail_data.distribution}
              cluster={@detail_data.cluster}
            />

            <.edge_history_chart_section
              edge_history={@detail_data.edge_history}
            />

            <.price_history_chart_section
              price_history={@detail_data.price_history}
              position={@detail_data.position}
            />

            <.distribution_section
              distribution={@detail_data.distribution}
              cluster={@detail_data.cluster}
            />

            <.model_breakdown_section snapshots={@detail_data.model_breakdown} />

            <.orderbook_section orderbook={@detail_data.orderbook} />

            <.metar_section metar={@detail_data.metar} />

            <.position_section position={@detail_data.position} />

            <.buy_controls_section
              signal={@detail_data.signal}
              station={@detail_data.station}
              cluster={@detail_data.cluster}
              detail_buy_amount={@detail_buy_amount}
              buying={@buying}
            />

            <.polymarket_link cluster={@detail_data.cluster} />
          </div>
        <% else %>
          <div class="flex items-center justify-center py-16">
            <div class="text-sm text-zinc-500 dark:text-zinc-400">Signal not found</div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp detail_header(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-base font-bold text-zinc-900 dark:text-zinc-100"><%= @station.code %></span>
        <span class="text-sm text-zinc-500 dark:text-zinc-400"><%= @station.city %></span>
      </div>
      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-sm font-medium text-zinc-700 dark:text-zinc-300"><%= @signal.outcome_label %></span>
        <span class="text-xs text-zinc-500 dark:text-zinc-400"><%= @cluster.target_date %></span>
        <span class={["font-bold text-sm", edge_color(@signal.edge)]}>
          <%= format_edge(@signal.edge) %>
        </span>
        <span class={["px-1.5 py-0.5 rounded text-[10px] font-medium", alert_class(@signal.alert_level)]}>
          <%= format_alert(@signal.alert_level) %>
        </span>
        <span class={["px-1.5 py-0.5 rounded text-[10px] font-medium", confidence_class(@signal.confidence)]}>
          <%= @signal.confidence || "-" %>
        </span>
      </div>
    </div>
    """
  end

  defp distribution_chart_section(assigns) do
    has_data = assigns.distribution != nil

    chart_data =
      if has_data do
        sorted =
          assigns.distribution.probabilities
          |> Enum.sort_by(fn {_label, prob} -> prob end, :desc)

        labels = Enum.map(sorted, fn {label, _prob} -> label end)
        model_probs = Enum.map(sorted, fn {_label, prob} -> Float.round(prob, 4) end)
        market_prices_map = build_market_price_map(assigns.cluster.outcomes)

        market_prices =
          Enum.map(labels, fn label -> Float.round(Map.get(market_prices_map, label, 0) * 1.0, 4) end)

        Jason.encode!(%{labels: labels, model_probs: model_probs, market_prices: market_prices})
      end

    assigns =
      assigns
      |> assign(:has_data, has_data)
      |> assign(:chart_data, chart_data)

    ~H"""
    <div class="space-y-2">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Cluster Distribution</h3>
      <div :if={!@has_data} class="text-xs text-zinc-400">No distribution data available</div>
      <div :if={@has_data} class="h-48">
        <canvas
          id="distribution-chart"
          phx-hook="ChartHook"
          data-chart-type="distribution"
          data-chart-data={@chart_data}
          class="w-full h-full"
        />
      </div>
    </div>
    """
  end

  defp edge_history_chart_section(assigns) do
    has_data = assigns.edge_history != []

    chart_data =
      if has_data do
        times = Enum.map(assigns.edge_history, fn h -> Calendar.strftime(h.time, "%H:%M") end)
        edges = Enum.map(assigns.edge_history, fn h -> Float.round(h.edge * 100, 1) end)
        model_probs = Enum.map(assigns.edge_history, fn h -> Float.round(h.model_prob * 100, 1) end)
        market_prices = Enum.map(assigns.edge_history, fn h -> Float.round(h.market_price * 100, 1) end)

        Jason.encode!(%{times: times, edges: edges, model_probs: model_probs, market_prices: market_prices})
      end

    assigns =
      assigns
      |> assign(:has_data, has_data)
      |> assign(:chart_data, chart_data)

    ~H"""
    <div class="space-y-2">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Edge History (24h)</h3>
      <div :if={!@has_data} class="text-xs text-zinc-400">No edge history available</div>
      <div :if={@has_data} class="h-48">
        <canvas
          id="edge-history-chart"
          phx-hook="ChartHook"
          data-chart-type="edge_history"
          data-chart-data={@chart_data}
          class="w-full h-full"
        />
      </div>
    </div>
    """
  end

  defp price_history_chart_section(assigns) do
    has_data = assigns.price_history != []

    chart_data =
      if has_data do
        valid_history = Enum.reject(assigns.price_history, fn h -> is_nil(h.yes_price) or is_nil(h.time) end)
        times = Enum.map(valid_history, fn h -> Calendar.strftime(h.time, "%H:%M") end)
        prices = Enum.map(valid_history, fn h -> Float.round(h.yes_price * 1.0, 4) end)

        buy_price =
          if assigns.position, do: assigns.position.avg_buy_price

        Jason.encode!(%{times: times, prices: prices, buy_price: buy_price})
      end

    assigns =
      assigns
      |> assign(:has_data, has_data)
      |> assign(:chart_data, chart_data)

    ~H"""
    <div class="space-y-2">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Price History (48h)</h3>
      <div :if={!@has_data} class="text-xs text-zinc-400">No price history available</div>
      <div :if={@has_data} class="h-48">
        <canvas
          id="price-history-chart"
          phx-hook="ChartHook"
          data-chart-type="price_history"
          data-chart-data={@chart_data}
          class="w-full h-full"
        />
      </div>
    </div>
    """
  end

  defp distribution_section(assigns) do
    outcomes =
      if assigns.distribution do
        assigns.distribution.probabilities
        |> Enum.sort_by(fn {_label, prob} -> prob end, :desc)
      else
        []
      end

    market_prices = build_market_price_map(assigns.cluster.outcomes)

    assigns =
      assigns
      |> assign(:outcomes, outcomes)
      |> assign(:market_prices, market_prices)

    ~H"""
    <div class="space-y-2">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Cluster Distribution</h3>
      <div :if={@outcomes == []} class="text-xs text-zinc-400">No distribution data available</div>
      <div :for={{label, model_prob} <- @outcomes} class="space-y-0.5">
        <div class="flex items-center justify-between text-xs">
          <span class="text-zinc-700 dark:text-zinc-300 w-24 truncate"><%= label %></span>
          <span class="text-zinc-500 dark:text-zinc-400">
            M: <%= format_pct(model_prob) %> | P: $<%= format_price(Map.get(@market_prices, label, 0)) %>
          </span>
        </div>
        <div class="flex gap-0.5 h-2">
          <div class="bg-blue-500 rounded-sm" style={"width: #{model_prob * 100}%"} title={"Model: #{format_pct(model_prob)}"}></div>
          <div class="bg-orange-400 rounded-sm" style={"width: #{Map.get(@market_prices, label, 0) * 100}%"} title={"Market: $#{format_price(Map.get(@market_prices, label, 0))}"}></div>
        </div>
        <div class="text-[10px] text-zinc-400">
          Edge: <%= format_edge(model_prob - Map.get(@market_prices, label, 0)) %>
        </div>
      </div>
    </div>
    """
  end

  defp model_breakdown_section(assigns) do
    ~H"""
    <div class="space-y-2">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Model Breakdown</h3>
      <div :if={@snapshots == []} class="text-xs text-zinc-400">No model data available</div>
      <div :if={@snapshots != []} class="space-y-1">
        <div
          :for={snapshot <- @snapshots}
          class="flex items-center justify-between text-xs py-1 border-b border-zinc-100 dark:border-zinc-800"
        >
          <span class="text-zinc-700 dark:text-zinc-300 font-medium"><%= snapshot.model %></span>
          <span class="text-zinc-600 dark:text-zinc-400"><%= snapshot.max_temp_c %>&deg;C</span>
        </div>
        <div class="text-xs text-zinc-500 dark:text-zinc-400 pt-1">
          Consensus: <%= consensus_count(@snapshots) %> models
        </div>
      </div>
    </div>
    """
  end

  defp orderbook_section(assigns) do
    ~H"""
    <div class="space-y-2">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Orderbook</h3>
      <div :if={@orderbook == nil} class="text-xs text-zinc-400">Orderbook unavailable</div>
      <div :if={@orderbook != nil} class="grid grid-cols-3 gap-2 text-xs">
        <div class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Best Bid</div>
          <div class="text-green-600 dark:text-green-400 font-medium">
            $<%= format_book_price(@orderbook.best_bid) %>
          </div>
          <div class="text-zinc-400 text-[10px]"><%= format_book_size(@orderbook.best_bid) %> shares</div>
        </div>
        <div class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Best Ask</div>
          <div class="text-red-600 dark:text-red-400 font-medium">
            $<%= format_book_price(@orderbook.best_ask) %>
          </div>
          <div class="text-zinc-400 text-[10px]"><%= format_book_size(@orderbook.best_ask) %> shares</div>
        </div>
        <div class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Spread</div>
          <div class="text-zinc-700 dark:text-zinc-300 font-medium">
            $<%= format_price(@orderbook.spread || 0) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp metar_section(assigns) do
    ~H"""
    <div :if={@metar != nil} class="space-y-2">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">METAR Conditions</h3>
      <div class="grid grid-cols-2 gap-2 text-xs">
        <div :if={@metar.conditions != nil} class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Current Temp</div>
          <div class="text-zinc-900 dark:text-zinc-100 font-medium"><%= @metar.conditions[:temperature_c] || @metar.conditions["temperature_c"] %>&deg;C</div>
        </div>
        <div :if={@metar.todays_high != nil} class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Today's Max Observed</div>
          <div class="text-zinc-900 dark:text-zinc-100 font-medium"><%= @metar.todays_high %>&deg;C</div>
        </div>
      </div>
    </div>
    """
  end

  defp position_section(assigns) do
    ~H"""
    <div :if={@position != nil} class="space-y-2">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Position</h3>
      <div class="grid grid-cols-2 gap-2 text-xs">
        <div class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Tokens</div>
          <div class="text-zinc-900 dark:text-zinc-100 font-medium"><%= format_tokens(@position.tokens) %></div>
        </div>
        <div class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Avg Buy Price</div>
          <div class="text-zinc-900 dark:text-zinc-100 font-medium">$<%= format_price(@position.avg_buy_price) %></div>
        </div>
        <div class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Current Price</div>
          <div class="text-zinc-900 dark:text-zinc-100 font-medium">$<%= format_price(@position.current_price) %></div>
        </div>
        <div class="space-y-1">
          <div class="text-zinc-500 dark:text-zinc-400">Unrealized P&amp;L</div>
          <div class={["font-medium", if((@position.unrealized_pnl || 0) >= 0, do: "text-green-600 dark:text-green-400", else: "text-red-600 dark:text-red-400")]}>
            $<%= format_price(@position.unrealized_pnl || 0) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp buy_controls_section(assigns) do
    default_amount = assigns.station.buy_amount_usdc || 5.0
    amount = assigns.detail_buy_amount || default_amount
    market_price = assigns.signal.market_price || 0.01

    estimated_tokens = if market_price > 0, do: amount / market_price, else: 0.0
    payout = estimated_tokens * 1.0
    return_pct = if amount > 0, do: (payout - amount) / amount * 100, else: 0.0

    assigns =
      assigns
      |> assign(:amount, amount)
      |> assign(:estimated_tokens, estimated_tokens)
      |> assign(:payout, payout)
      |> assign(:return_pct, return_pct)

    ~H"""
    <div class="space-y-3 border-t border-zinc-200 dark:border-zinc-700 pt-4">
      <h3 class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase tracking-wider">Buy</h3>

      <form phx-change="update_buy_amount" class="space-y-2">
        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Amount (USDC)</label>
          <input
            type="number"
            name="buy_amount"
            value={@amount}
            min="0.1"
            step="0.5"
            phx-debounce="300"
            class="block w-full text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          />
        </div>

        <div class="grid grid-cols-3 gap-2 text-xs">
          <div class="space-y-0.5">
            <div class="text-zinc-500 dark:text-zinc-400">Est. Tokens</div>
            <div class="text-zinc-900 dark:text-zinc-100 font-medium"><%= format_tokens(@estimated_tokens) %></div>
          </div>
          <div class="space-y-0.5">
            <div class="text-zinc-500 dark:text-zinc-400">Payout if Wins</div>
            <div class="text-zinc-900 dark:text-zinc-100 font-medium">$<%= format_price(@payout) %></div>
          </div>
          <div class="space-y-0.5">
            <div class="text-zinc-500 dark:text-zinc-400">Return</div>
            <div class="text-green-600 dark:text-green-400 font-medium"><%= format_return(@return_pct) %></div>
          </div>
        </div>

        <div class="flex gap-2 pt-1">
          <button
            type="button"
            phx-click="buy_from_detail"
            phx-value-side="YES"
            disabled={@buying}
            class="flex-1 px-3 py-2 rounded-lg text-xs font-medium bg-green-600 hover:bg-green-700 text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <%= if @buying, do: "Placing...", else: "BUY YES" %>
          </button>
          <button
            type="button"
            phx-click="buy_from_detail"
            phx-value-side="NO"
            disabled={@buying}
            class="flex-1 px-3 py-2 rounded-lg text-xs font-medium bg-blue-600 hover:bg-blue-700 text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <%= if @buying, do: "Placing...", else: "BUY NO" %>
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp polymarket_link(assigns) do
    ~H"""
    <div :if={@cluster.event_slug} class="pt-2">
      <a
        href={"https://polymarket.com/event/#{@cluster.event_slug}"}
        target="_blank"
        rel="noopener noreferrer"
        class="text-xs text-blue-600 dark:text-blue-400 hover:underline"
      >
        Open on Polymarket &rarr;
      </a>
    </div>
    """
  end

  @impl true
  def handle_event("set_view", %{"mode" => mode}, socket) when mode in ~w(table grouped heatmap) do
    {:noreply, assign(socket, :view_mode, String.to_existing_atom(mode))}
  end

  def handle_event("update_filter", params, socket) do
    filters = socket.assigns.filters

    updated_filters =
      filters
      |> maybe_update_stations(params)
      |> maybe_update_string(params, "resolution_date", :resolution_date)
      |> maybe_update_string(params, "side", :side)
      |> maybe_update_string(params, "alert_level", :alert_level)
      |> maybe_update_string(params, "sort_by", :sort_by)
      |> maybe_update_string(params, "has_position", :has_position)
      |> maybe_update_number(params, "min_edge", :min_edge)
      |> maybe_update_float(params, "max_price", :max_price)

    reload_signals(socket, updated_filters)
  end

  def handle_event("toggle_actionable", _params, socket) do
    filters = Map.update!(socket.assigns.filters, :actionable_only, &(!&1))
    reload_signals(socket, filters)
  end

  def handle_event("clear_filters", _params, socket) do
    reload_signals(socket, default_filters())
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected

    updated =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    {:noreply, assign(socket, :selected, updated)}
  end

  def handle_event("open_detail", %{"id" => id}, socket) do
    signal_id = String.to_integer(id)
    send(self(), {:load_detail, signal_id})

    {:noreply,
     assign(socket,
       detail_signal_id: signal_id,
       detail_data: nil,
       detail_loading: true,
       detail_buy_amount: nil
     )}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply,
     assign(socket,
       detail_signal_id: nil,
       detail_data: nil,
       detail_loading: false
     )}
  end

  def handle_event("filter_station", %{"code" => code}, socket) do
    filters = %{socket.assigns.filters | stations: [code]}
    reload_signals(socket, filters)
  end

  def handle_event("heatmap_click", %{"station" => station, "date" => date_str}, socket) do
    resolution_date = heatmap_date_to_filter(date_str)

    filters =
      %{default_filters() | stations: [station], resolution_date: resolution_date}

    socket =
      socket
      |> assign(:view_mode, :table)
      |> do_reload_signals(filters)

    {:noreply, socket}
  end

  def handle_event("buy_selected", _params, socket) do
    selected = socket.assigns.selected
    signals = socket.assigns.signals
    balance = socket.assigns.balance || 0.0
    selected_count = MapSet.size(selected)

    selected_signals =
      Enum.filter(signals, fn row -> MapSet.member?(selected, row.signal.id) end)

    buy_amount = socket.assigns.detail_buy_amount

    estimated_cost =
      Enum.reduce(selected_signals, 0.0, fn row, acc ->
        acc + (buy_amount || row.station.buy_amount_usdc || 1.0)
      end)

    min_reserve = Application.get_env(:weather_edge, :trading)[:min_reserve_usdc] || 0.50

    cond do
      selected_count == 0 ->
        {:noreply, put_flash(socket, :error, "No signals selected")}

      selected_count > 10 ->
        {:noreply, put_flash(socket, :error, "Maximum 10 signals can be bought at once")}

      Enum.any?(selected_signals, fn row -> row.position != nil end) ->
        {:noreply, put_flash(socket, :error, "Some selected signals already have positions")}

      balance < estimated_cost + min_reserve ->
        {:noreply,
         put_flash(socket, :error, "Insufficient balance: $#{format_price(balance)} available, $#{format_price(estimated_cost + min_reserve)} needed")}

      true ->
        send(self(), {:execute_buy_batch, selected_signals})

        {:noreply,
         socket
         |> assign(:buying, true)
         |> assign(:buy_progress, "Preparing...")}
    end
  end

  def handle_event("update_buy_amount", %{"buy_amount" => amount_str}, socket) do
    case Float.parse(to_string(amount_str)) do
      {amount, _} when amount > 0 ->
        {:noreply, assign(socket, :detail_buy_amount, amount)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("buy_from_detail", %{"side" => side}, socket) when side in ~w(YES NO) do
    detail_data = socket.assigns.detail_data

    if detail_data == nil do
      {:noreply, put_flash(socket, :error, "No signal detail loaded")}
    else
      signal = detail_data.signal
      cluster = detail_data.cluster
      station = detail_data.station
      default_amount = station.buy_amount_usdc || 1.0
      amount = socket.assigns.detail_buy_amount || default_amount

      token_id = find_token_id(cluster.outcomes, signal.outcome_label)

      if is_nil(token_id) do
        {:noreply, put_flash(socket, :error, "No token ID found for #{signal.outcome_label}")}
      else
        outcome = %{
          "token_id" => token_id,
          "outcome_label" => signal.outcome_label,
          "price" => signal.market_price,
          "market_cluster_id" => cluster.id,
          "event_id" => cluster.event_slug,
          "auto_order" => false
        }

        # Run async to avoid blocking LiveView (OrderManager has 30s retry)
        lv = self()
        Task.start(fn ->
          result = OrderManager.place_buy_order(signal.station_code, outcome, amount)
          send(lv, {:detail_buy_result, side, signal, amount, result})
        end)

        {:noreply, assign(socket, :buying, true)}
      end
    end
  end

  def handle_info({:detail_buy_result, side, signal, amount, result}, socket) do
    socket = assign(socket, :buying, false)

    case result do
      {:ok, _order} ->
        updated_detail = DetailData.fetch_signal_detail(signal.id)

        {:noreply,
         socket
         |> put_flash(:info, "#{side} order placed for #{signal.outcome_label} ($#{format_price(amount)})")
         |> assign(:detail_data, updated_detail)
         |> then(&do_reload_signals(&1, &1.assigns.filters))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Order failed: #{inspect(reason)}")}
    end
  end

  def handle_event("buy_best", %{"signal-id" => signal_id_str}, socket) do
    signal_id = String.to_integer(signal_id_str)

    case find_signal_row(socket.assigns.signals, signal_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Signal not found")}

      row ->
        execute_single_buy(socket, row)
    end
  end

  def handle_event("buy_best_hedge", %{"best-id" => best_id_str, "hedge-id" => hedge_id_str}, socket) do
    best_id = String.to_integer(best_id_str)
    hedge_id = String.to_integer(hedge_id_str)
    signals = socket.assigns.signals

    best_row = find_signal_row(signals, best_id)
    hedge_row = find_signal_row(signals, hedge_id)

    cond do
      best_row == nil or hedge_row == nil ->
        {:noreply, put_flash(socket, :error, "Signal not found")}

      true ->
        send(self(), {:execute_buy_batch, [best_row, hedge_row]})

        {:noreply,
         socket
         |> assign(:buying, true)
         |> assign(:buy_progress, "Preparing...")}
    end
  end

  def handle_event("load_more", _params, socket) do
    new_offset = socket.assigns.offset + 20

    more_signals =
      Queries.list_filtered_signals(socket.assigns.filters, offset: new_offset)

    {:noreply,
     assign(socket,
       signals: socket.assigns.signals ++ more_signals,
       offset: new_offset
     )}
  end

  def handle_event("export_signals", _params, socket) do
    signals = socket.assigns.signals
    export = build_export(signals)
    json = Jason.encode!(export, pretty: true)

    {:noreply, push_event(socket, "download_json", %{data: json, filename: "signals_export_#{Date.utc_today()}.json"})}
  end

  def handle_event("toggle_performance", _params, socket) do
    expanded = !socket.assigns.performance_expanded

    socket = assign(socket, :performance_expanded, expanded)

    if expanded && socket.assigns.performance_data == nil do
      send(self(), :load_performance)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_performance, socket) do
    performance_data = Performance.compute_stats()
    {:noreply, assign(socket, :performance_data, performance_data)}
  end

  def handle_info({:load_detail, signal_id}, socket) do
    if socket.assigns.detail_signal_id == signal_id do
      detail_data = DetailData.fetch_signal_detail(signal_id)

      {:noreply,
       assign(socket,
         detail_data: detail_data,
         detail_loading: false
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:execute_buy_batch, selected_signals}, socket) do
    total = length(selected_signals)
    results = execute_orders_sequentially(selected_signals, total, socket)

    succeeded = Enum.count(results, fn {status, _} -> status == :ok end)
    failed = total - succeeded

    socket =
      socket
      |> assign(:buying, false)
      |> assign(:buy_progress, nil)
      |> assign(:selected, MapSet.new())

    socket = do_reload_signals(socket, socket.assigns.filters)

    socket =
      cond do
        failed == 0 ->
          put_flash(socket, :info, "Successfully bought #{succeeded} signal(s)")

        succeeded == 0 ->
          put_flash(socket, :error, "All #{failed} orders failed")

        true ->
          put_flash(socket, :info, "Bought #{succeeded} signal(s), #{failed} failed")
      end

    {:noreply, socket}
  end

  def handle_info({:buy_progress, n, total}, socket) do
    {:noreply, assign(socket, :buy_progress, "Buying #{n}/#{total}...")}
  end

  def handle_info({:new_signal, signal}, socket) do
    filters = socket.assigns.filters

    if signal_matches_filters?(signal, filters) do
      row = build_signal_row(signal)

      signals = [row | socket.assigns.signals]
      total_count = socket.assigns.total_count + 1
      highlighted = MapSet.put(socket.assigns[:highlighted] || MapSet.new(), signal.id)

      socket =
        socket
        |> assign(:signals, signals)
        |> assign(:total_count, total_count)
        |> assign(:highlighted, highlighted)

      Process.send_after(self(), {:clear_highlight, signal.id}, 3_000)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:clear_highlight, signal_id}, socket) do
    highlighted =
      (socket.assigns[:highlighted] || MapSet.new())
      |> MapSet.delete(signal_id)

    {:noreply, assign(socket, :highlighted, highlighted)}
  end

  def handle_info({:balance_updated, balance}, socket) do
    {:noreply, assign(socket, :balance, balance)}
  end

  def handle_info({:position_updated, position}, socket) do
    signals =
      Enum.map(socket.assigns.signals, fn row ->
        if row.signal.market_cluster_id == position.market_cluster_id &&
             row.signal.outcome_label == position.outcome_label &&
             position.status == "open" do
          %{
            row
            | position: %{
                id: position.id,
                tokens: position.tokens,
                avg_buy_price: position.avg_buy_price,
                current_price: position.current_price,
                unrealized_pnl: position.unrealized_pnl,
                side: position.side
              }
          }
        else
          row
        end
      end)

    {:noreply, assign(socket, :signals, signals)}
  end

  def handle_info({:positions_synced, _positions}, socket) do
    {:noreply, do_reload_signals(socket, socket.assigns.filters)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp reload_signals(socket, filters) do
    {:noreply, do_reload_signals(socket, filters)}
  end

  defp do_reload_signals(socket, filters) do
    signals = Queries.list_filtered_signals(filters)
    total_count = Queries.count_filtered_signals(filters)

    assign(socket,
      filters: filters,
      signals: signals,
      total_count: total_count,
      offset: 0
    )
  end

  defp find_signal_row(signals, signal_id) do
    Enum.find(signals, fn row -> row.signal.id == signal_id end)
  end

  defp execute_single_buy(socket, row) do
    amount = socket.assigns.detail_buy_amount || row.station.buy_amount_usdc || 1.0
    outcome = build_outcome(row)

    case OrderManager.place_buy_order(row.signal.station_code, outcome, amount) do
      {:ok, _order} ->
        socket = do_reload_signals(socket, socket.assigns.filters)

        {:noreply,
         put_flash(socket, :info, "Order placed for #{row.signal.outcome_label} ($#{format_price(amount)})")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Order failed: #{inspect(reason)}")}
    end
  end

  defp execute_orders_sequentially(selected_signals, total, socket) do
    buy_amount = socket.assigns.detail_buy_amount

    selected_signals
    |> Enum.with_index(1)
    |> Enum.map(fn {row, n} ->
      send(self(), {:buy_progress, n, total})

      amount = buy_amount || row.station.buy_amount_usdc || 1.0

      outcome = build_outcome(row)

      case OrderManager.place_buy_order(row.signal.station_code, outcome, amount) do
        {:ok, order} -> {:ok, order}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp build_outcome(row) do
    token_id = find_token_id(row.cluster.outcomes, row.signal.outcome_label)

    %{
      "token_id" => token_id,
      "outcome_label" => row.signal.outcome_label,
      "price" => row.signal.market_price,
      "market_cluster_id" => row.cluster.id,
      "event_id" => row.cluster.event_slug,
      "auto_order" => false
    }
  end

  defp find_token_id(outcomes, outcome_label) when is_list(outcomes) do
    match = Enum.find(outcomes, fn o ->
      o["outcome_label"] == outcome_label || o["label"] == outcome_label
    end)

    case match do
      %{"token_id" => token_id} when not is_nil(token_id) -> strip_quotes(token_id)
      %{"clob_token_ids" => [yes_token | _]} -> strip_quotes(yes_token)
      %{"clob_token_ids" => token} when is_binary(token) -> strip_quotes(token)
      nil ->
        require Logger
        labels = Enum.map(outcomes, fn o -> o["outcome_label"] || o["label"] end)
        Logger.warning("find_token_id: no match for '#{outcome_label}' in #{inspect(labels)}")
        nil
      _ -> nil
    end
  end

  defp find_token_id(outcomes, outcome_label) when is_map(outcomes) do
    case Map.get(outcomes, outcome_label) do
      %{"token_id" => token_id} -> token_id
      %{"clob_token_ids" => [yes_token | _]} -> yes_token
      _ -> nil
    end
  end

  defp find_token_id(_, _), do: nil

  defp strip_quotes(s) when is_binary(s), do: String.replace(s, "\"", "")
  defp strip_quotes(s), do: s

  defp maybe_update_stations(filters, %{"stations" => stations}) when is_list(stations) do
    %{filters | stations: stations}
  end

  defp maybe_update_stations(filters, _), do: filters

  defp maybe_update_string(filters, params, key, field) do
    case Map.get(params, key) do
      nil -> filters
      val -> Map.put(filters, field, val)
    end
  end

  defp maybe_update_number(filters, params, key, field) do
    case Map.get(params, key) do
      nil -> filters
      "" -> Map.put(filters, field, nil)
      val ->
        case Integer.parse(to_string(val)) do
          {num, _} -> Map.put(filters, field, num)
          :error -> filters
        end
    end
  end

  defp maybe_update_float(filters, params, key, field) do
    case Map.get(params, key) do
      nil -> filters
      "" -> Map.put(filters, field, nil)
      val ->
        case Float.parse(to_string(val)) do
          {num, _} -> Map.put(filters, field, num)
          :error -> filters
        end
    end
  end

  defp count_active_filters(filters) do
    defaults = default_filters()

    Enum.count(Map.keys(defaults), fn key ->
      Map.get(filters, key) != Map.get(defaults, key)
    end)
  end

  defp stale_signal?(row) do
    signal_price = row.signal.market_price
    current_price = current_outcome_price(row.cluster.outcomes, row.signal.outcome_label)

    cond do
      is_nil(signal_price) or is_nil(current_price) or current_price == 0 -> false
      abs(signal_price - current_price) / current_price > 0.10 -> true
      true -> false
    end
  end

  defp current_outcome_price(outcomes, outcome_label) when is_list(outcomes) do
    case Enum.find(outcomes, fn o ->
           (o["outcome_label"] || o["label"]) == outcome_label
         end) do
      %{"price" => price} when is_number(price) -> price
      %{"yes_price" => price} when is_number(price) -> price
      _ -> nil
    end
  end

  defp current_outcome_price(_, _), do: nil

  defp signal_matches_filters?(signal, filters) do
    station_match =
      filters.stations == [] || signal.station_code in filters.stations

    edge_match =
      is_nil(filters.min_edge) || (signal.edge && signal.edge * 100 >= filters.min_edge)

    side_match =
      filters.side == "all" || signal.recommended_side == filters.side

    alert_match =
      filters.alert_level == "all" || signal.alert_level == filters.alert_level

    station_match && edge_match && side_match && alert_match
  end

  defp build_signal_row(signal) do
    cluster = WeatherEdge.Repo.get(WeatherEdge.Markets.MarketCluster, signal.market_cluster_id)
    station = WeatherEdge.Repo.get_by(WeatherEdge.Stations.Station, code: signal.station_code)

    position =
      WeatherEdge.Repo.one(
        from(p in WeatherEdge.Trading.Position,
          where:
            p.market_cluster_id == ^signal.market_cluster_id and
              p.outcome_label == ^signal.outcome_label and
              p.status == "open",
          limit: 1
        )
      )

    hours_to_resolution =
      if cluster && cluster.target_date do
        target_datetime = DateTime.new!(cluster.target_date, ~T[23:59:59], "Etc/UTC")
        DateTime.diff(target_datetime, DateTime.utc_now(), :hour) |> max(0)
      else
        nil
      end

    %{
      signal: %{
        id: signal.id,
        computed_at: signal.computed_at,
        station_code: signal.station_code,
        outcome_label: signal.outcome_label,
        model_probability: signal.model_probability,
        market_price: signal.market_price,
        edge: signal.edge,
        recommended_side: signal.recommended_side,
        alert_level: signal.alert_level,
        confidence: signal.confidence,
        market_cluster_id: signal.market_cluster_id
      },
      cluster:
        if cluster do
          %{
            id: cluster.id,
            target_date: cluster.target_date,
            title: cluster.title,
            event_slug: cluster.event_slug,
            outcomes: cluster.outcomes
          }
        else
          %{id: nil, target_date: nil, title: nil, event_slug: nil, outcomes: []}
        end,
      station:
        if station do
          %{
            code: station.code,
            city: station.city,
            max_buy_price: station.max_buy_price,
            buy_amount_usdc: station.buy_amount_usdc
          }
        else
          %{code: signal.station_code, city: nil, max_buy_price: nil, buy_amount_usdc: nil}
        end,
      position:
        if position do
          %{
            id: position.id,
            tokens: position.tokens,
            avg_buy_price: position.avg_buy_price,
            current_price: position.current_price,
            unrealized_pnl: position.unrealized_pnl,
            side: position.side
          }
        else
          nil
        end,
      hours_to_resolution: hours_to_resolution
    }
  end

  defp default_filters do
    %{
      stations: [],
      min_edge: 8,
      resolution_date: "all",
      side: "all",
      max_price: nil,
      alert_level: "all",
      sort_by: "edge_desc",
      actionable_only: false,
      has_position: "all"
    }
  end

  defp heatmap_date_to_filter(date_str) do
    date = Date.from_iso8601!(date_str)
    today = Date.utc_today()

    case Date.diff(date, today) do
      0 -> "today"
      1 -> "tomorrow"
      2 -> "+2d"
      3 -> "+3d"
      _ -> "all"
    end
  end

  # Detail panel helpers

  defp build_market_price_map(outcomes) when is_list(outcomes) do
    Map.new(outcomes, fn o ->
      label = o["outcome_label"] || o["label"] || ""
      price = o["price"] || o["yes_price"] || 0
      {label, price}
    end)
  end

  defp build_market_price_map(_), do: %{}

  defp consensus_count(snapshots) when is_list(snapshots) do
    snapshots
    |> Enum.map(& &1.max_temp_c)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_temp, count} -> count end, fn -> {nil, 0} end)
    |> elem(1)
  end

  defp consensus_count(_), do: 0

  defp format_book_price(nil), do: "-"
  defp format_book_price(%{"price" => price}), do: format_price(parse_book_val(price))
  defp format_book_price(%{price: price}), do: format_price(parse_book_val(price))
  defp format_book_price(_), do: "-"

  defp format_book_size(nil), do: "-"
  defp format_book_size(%{"size" => size}), do: format_price(parse_book_val(size))
  defp format_book_size(%{size: size}), do: format_price(parse_book_val(size))
  defp format_book_size(_), do: "-"

  defp parse_book_val(val) when is_binary(val) do
    case Float.parse(val) do
      {num, _} -> num
      :error -> 0.0
    end
  end

  defp parse_book_val(val) when is_number(val), do: val * 1.0
  defp parse_book_val(_), do: 0.0

  # Formatting helpers

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_time(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%H:%M")
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

  defp edge_color(nil), do: "text-zinc-400"
  defp edge_color(val) when is_number(val) and val > 0.15, do: "text-green-600 dark:text-green-400"
  defp edge_color(val) when is_number(val) and val > 0.08, do: "text-yellow-600 dark:text-yellow-400"
  defp edge_color(_), do: "text-zinc-400"

  defp alert_class("extreme"), do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
  defp alert_class("strong"), do: "bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400"
  defp alert_class("opportunity"), do: "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400"
  defp alert_class("safe_no"), do: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
  defp alert_class(_), do: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"

  defp format_alert("safe_no"), do: "Safe NO"
  defp format_alert(nil), do: "-"
  defp format_alert(level), do: String.capitalize(level)

  defp confidence_class("confirmed"), do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400"
  defp confidence_class("high"), do: "bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-400"
  defp confidence_class("forecast"), do: "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-500"
  defp confidence_class(_), do: "bg-zinc-50 text-zinc-400 dark:bg-zinc-800 dark:text-zinc-500"

  defp format_volume(nil, _), do: "-"

  defp format_volume(outcomes, outcome_label) when is_list(outcomes) do
    case Enum.find(outcomes, fn o -> o["outcome_label"] == outcome_label || o["label"] == outcome_label end) do
      %{"liquidity" => liq} when is_number(liq) -> "$#{format_price(liq)}"
      _ -> "-"
    end
  end

  defp format_volume(outcomes, outcome_label) when is_map(outcomes) do
    case Map.get(outcomes, outcome_label) do
      %{"liquidity" => liq} when is_number(liq) -> "$#{format_price(liq)}"
      _ -> "-"
    end
  end

  defp format_volume(_, _), do: "-"

  defp format_return(val) when is_number(val) do
    sign = if val >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(val * 1.0, decimals: 1)}%"
  end

  defp format_return(_), do: "-"

  defp format_tokens(nil), do: "-"
  defp format_tokens(tokens) when is_number(tokens), do: :erlang.float_to_binary(tokens * 1.0, decimals: 1)

  defp trend_arrow(:up), do: "↑"
  defp trend_arrow(:down), do: "↓"
  defp trend_arrow(:flat), do: "→"

  defp trend_color(:up), do: "text-green-600 dark:text-green-400"
  defp trend_color(:down), do: "text-red-600 dark:text-red-400"
  defp trend_color(:flat), do: "text-zinc-400"

  defp format_trend_delta(delta) when is_number(delta) do
    :erlang.float_to_binary(abs(delta * 1.0), decimals: 2)
  end

  defp format_trend_delta(_), do: ""

  defp pnl_color(nil), do: "text-zinc-400"
  defp pnl_color(val) when is_number(val) and val > 0, do: "text-green-600 dark:text-green-400"
  defp pnl_color(val) when is_number(val) and val < 0, do: "text-red-600 dark:text-red-400"
  defp pnl_color(_), do: "text-zinc-400"

  defp result_class("won"), do: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
  defp result_class("lost"), do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
  defp result_class("sold"), do: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"
  defp result_class(_), do: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"

  # --- Export ---

  defp build_export(signals) do
    # Group signals by station+cluster to avoid redundant lookups
    grouped = Enum.group_by(signals, fn row -> {row.signal.station_code, row.cluster.id} end)

    entries =
      Enum.flat_map(grouped, fn {{station_code, cluster_id}, rows} ->
        cluster = hd(rows).cluster
        station = hd(rows).station
        target_date = cluster.target_date

        # Forecast model snapshots
        forecasts = export_forecasts(station_code, target_date)

        # METAR observed temperature
        metar = export_metar(station_code)

        # Peak status
        peak = export_peak_status(station_code)

        # Distribution from engine (with correct temp unit)
        temp_unit =
          case Stations.get_by_code(station_code) do
            {:ok, s} -> s.temp_unit || "C"
            _ -> "C"
          end

        distribution = export_distribution(station_code, target_date, temp_unit)

        Enum.map(rows, fn row ->
          %{
            signal: %{
              id: row.signal.id,
              computed_at: to_string(row.signal.computed_at),
              station_code: row.signal.station_code,
              outcome_label: row.signal.outcome_label,
              model_probability: row.signal.model_probability,
              market_price: row.signal.market_price,
              edge: row.signal.edge,
              edge_pct: if(row.signal.edge, do: Float.round(row.signal.edge * 100, 2)),
              recommended_side: row.signal.recommended_side,
              alert_level: row.signal.alert_level,
              confidence: row.signal.confidence
            },
            cluster: %{
              id: cluster_id,
              title: cluster.title,
              target_date: to_string(target_date),
              event_slug: cluster.event_slug,
              polymarket_url: "https://polymarket.com/event/#{cluster.event_slug}",
              outcomes:
                Enum.map(cluster.outcomes || [], fn o ->
                  %{
                    label: o["outcome_label"],
                    yes_price: o["yes_price"],
                    no_price: o["no_price"],
                    volume: o["volume"],
                    liquidity: o["liquidity"]
                  }
                end)
            },
            station: %{
              code: station.code,
              city: station.city
            },
            position: row.position,
            diagnostics: %{
              forecasts: forecasts,
              metar: metar,
              peak_status: peak,
              distribution: distribution
            }
          }
        end)
      end)

    %{
      exported_at: DateTime.utc_now() |> to_string(),
      signal_count: length(entries),
      signals: entries
    }
  end

  defp export_forecasts(_station_code, nil), do: %{error: "no target date"}

  defp export_forecasts(station_code, target_date) do
    snapshots = WeatherEdge.Forecasts.latest_snapshots(station_code, target_date)

    Enum.map(snapshots, fn s ->
      %{
        model: s.model,
        max_temp_c: s.max_temp_c,
        fetched_at: to_string(s.fetched_at)
      }
    end)
  end

  defp export_metar(station_code) do
    case WeatherEdge.Forecasts.MetarClient.get_todays_high(station_code) do
      {:ok, temp_c} -> %{observed_high_c: temp_c}
      {:error, reason} -> %{error: inspect(reason)}
    end
  end

  defp export_peak_status(station_code) do
    case Stations.get_by_code(station_code) do
      {:ok, station} ->
        {status, hours} = WeatherEdge.Timezone.PeakCalculator.peak_status(station.longitude)
        confidence = WeatherEdge.Timezone.PeakCalculator.confidence(status)

        %{
          status: to_string(status),
          hours_to_peak: hours,
          confidence: to_string(confidence)
        }

      _ ->
        %{error: "station not found"}
    end
  end

  defp export_distribution(_station_code, nil, _temp_unit), do: %{error: "no target date"}

  defp export_distribution(station_code, target_date, temp_unit) do
    case WeatherEdge.Probability.Engine.compute_distribution(station_code, target_date, temp_unit: temp_unit) do
      {:ok, dist} ->
        probs =
          dist.probabilities
          |> Enum.sort_by(fn {label, _} -> label end)
          |> Enum.map(fn {label, prob} ->
            %{label: label, probability: Float.round(prob, 4)}
          end)

        %{
          labels: Enum.map(probs, & &1.label),
          probabilities: probs
        }

      {:error, reason} ->
        %{error: inspect(reason)}
    end
  end
end
