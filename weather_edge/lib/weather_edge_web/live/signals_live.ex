defmodule WeatherEdgeWeb.SignalsLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.PubSubHelper
  alias WeatherEdge.Signals.Queries
  alias WeatherEdge.Signals.DetailData
  alias WeatherEdge.Stations
  alias WeatherEdge.Markets
  alias WeatherEdge.Trading.OrderManager

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
       buy_progress: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.dashboard_header balance={@balance} wallet_address={@wallet_address} />

      <div class="sticky top-0 z-30 rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4 space-y-3">
        <div class="flex items-center justify-between">
          <.filter_bar filters={@filters} station_codes={@station_codes} total_count={@total_count} signals_count={length(@signals)} />
          <.view_mode_toggle view_mode={@view_mode} />
        </div>
      </div>

      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900">
        <%= if @view_mode == :table do %>
          <.signals_table signals={@signals} selected={@selected} total_count={@total_count} />
        <% else %>
          <div class="p-4">
            <p class="text-sm text-zinc-500 dark:text-zinc-400">
              <%= @view_mode %> view | Showing <%= length(@signals) %> of <%= @total_count %> signals
            </p>
          </div>
        <% end %>
      </div>

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
      />

      <div
        :if={@detail_signal_id != nil}
        phx-click="close_detail"
        class="fixed inset-0 z-40 bg-black/20"
      />
    </div>
    """
  end

  defp quick_actions_bar(assigns) do
    selected_signals = Enum.filter(assigns.signals, fn row -> MapSet.member?(assigns.selected, row.signal.id) end)
    estimated_cost = Enum.reduce(selected_signals, 0.0, fn row, acc -> acc + (row.station.buy_amount_usdc || 5.0) end)
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
            class="border-b border-zinc-100 dark:border-zinc-800 hover:bg-zinc-50 dark:hover:bg-zinc-800/50 cursor-pointer transition-colors"
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
            <td class="px-3 py-2 text-zinc-700 dark:text-zinc-300">
              $<%= format_price(row.signal.market_price) %>
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
    <div class="flex-1 space-y-3">
      <div class="flex flex-wrap gap-3 items-end">
        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Stations</label>
          <select
            name="stations"
            multiple
            phx-change="update_filter"
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
            phx-change="update_filter"
            class="block w-20 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Resolution</label>
          <select
            name="resolution_date"
            phx-change="update_filter"
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
            phx-change="update_filter"
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
            phx-change="update_filter"
            class="block w-20 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Alert Level</label>
          <select
            name="alert_level"
            phx-change="update_filter"
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
            phx-change="update_filter"
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
            phx-change="update_filter"
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
    </div>
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

      <div class="space-y-2">
        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Amount (USDC)</label>
          <input
            type="number"
            name="buy_amount"
            value={@amount}
            min="0.1"
            step="0.5"
            phx-change="update_buy_amount"
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
            phx-click="buy_from_detail"
            phx-value-side="YES"
            class="flex-1 px-3 py-2 rounded-lg text-xs font-medium bg-green-600 hover:bg-green-700 text-white transition-colors"
          >
            BUY YES
          </button>
          <button
            phx-click="buy_from_detail"
            phx-value-side="NO"
            class="flex-1 px-3 py-2 rounded-lg text-xs font-medium bg-blue-600 hover:bg-blue-700 text-white transition-colors"
          >
            BUY NO
          </button>
        </div>
      </div>
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

  def handle_event("buy_selected", _params, socket) do
    selected = socket.assigns.selected
    signals = socket.assigns.signals
    balance = socket.assigns.balance || 0.0
    selected_count = MapSet.size(selected)

    selected_signals =
      Enum.filter(signals, fn row -> MapSet.member?(selected, row.signal.id) end)

    estimated_cost =
      Enum.reduce(selected_signals, 0.0, fn row, acc ->
        acc + (row.station.buy_amount_usdc || 5.0)
      end)

    min_reserve = 2.0

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
      default_amount = station.buy_amount_usdc || 5.0
      amount = socket.assigns.detail_buy_amount || default_amount

      token_id = find_token_id(cluster.outcomes, signal.outcome_label)

      outcome = %{
        "token_id" => token_id,
        "outcome_label" => signal.outcome_label,
        "price" => signal.market_price,
        "market_cluster_id" => cluster.id,
        "event_id" => cluster.event_slug,
        "auto_order" => false
      }

      case OrderManager.place_buy_order(signal.station_code, outcome, amount) do
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

  @impl true
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

  defp execute_orders_sequentially(selected_signals, total, _socket) do
    selected_signals
    |> Enum.with_index(1)
    |> Enum.map(fn {row, n} ->
      send(self(), {:buy_progress, n, total})

      amount = row.station.buy_amount_usdc || 5.0

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
    case Enum.find(outcomes, fn o -> o["outcome_label"] == outcome_label || o["label"] == outcome_label end) do
      %{"token_id" => token_id} -> token_id
      _ -> nil
    end
  end

  defp find_token_id(outcomes, outcome_label) when is_map(outcomes) do
    case Map.get(outcomes, outcome_label) do
      %{"token_id" => token_id} -> token_id
      _ -> nil
    end
  end

  defp find_token_id(_, _), do: nil

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
end
