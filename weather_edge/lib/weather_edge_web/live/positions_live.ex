defmodule WeatherEdgeWeb.PositionsLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.PubSubHelper

  import WeatherEdgeWeb.Components.HeaderComponent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "dutch:price_update")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "dutch:new_position")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "dutch:sold")
      Phoenix.PubSub.subscribe(WeatherEdge.PubSub, "dutch:resolved")
      PubSubHelper.subscribe(PubSubHelper.portfolio_balance_update())
    end

    open_positions = dutch_call(:list_open_with_orders, [], [])
    history = dutch_call(:list_closed, [[limit: 20]], [])
    stats = dutch_call(:compute_performance_stats, [], default_stats())

    wallet_address = Application.get_env(:weather_edge, :polymarket)[:wallet_address]
    cached_balance = :persistent_term.get(:sidecar_balance, nil)

    {:ok,
     assign(socket,
       open_positions: open_positions,
       history: history,
       stats: stats,
       balance: cached_balance,
       wallet_address: wallet_address,
       selling: nil,
       sell_progress: nil,
       confirm_sell: nil,
       history_expanded: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 pb-24">
      <.dashboard_header balance={@balance} wallet_address={@wallet_address} />

      <%!-- Summary Bar --%>
      <.summary_bar open_positions={@open_positions} stats={@stats} />

      <%!-- Open Position Cards --%>
      <div :if={@open_positions == []} class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-8 text-center">
        <p class="text-sm text-zinc-400 dark:text-zinc-500">
          No open dutching positions. Positions will appear here when the dutching strategy places orders.
        </p>
      </div>

      <div :for={group <- @open_positions} class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900">
        <.position_card
          group={group}
          selling={@selling}
          sell_progress={@sell_progress}
        />
      </div>

      <%!-- Sell Confirmation Modal --%>
      <.sell_confirmation_modal
        :if={@confirm_sell != nil}
        group={@confirm_sell}
      />

      <%!-- History Section --%>
      <.history_section
        history={@history}
        history_expanded={@history_expanded}
      />

      <%!-- Performance Stats Bar --%>
      <.performance_stats_bar stats={@stats} />
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────
  # Components
  # ──────────────────────────────────────────────────────────

  defp summary_bar(assigns) do
    total_invested =
      Enum.reduce(assigns.open_positions, 0.0, fn g, acc ->
        acc + (Map.get(g, :total_invested, 0.0) || 0.0)
      end)

    current_value =
      Enum.reduce(assigns.open_positions, 0.0, fn g, acc ->
        acc + (Map.get(g, :current_value, 0.0) || 0.0)
      end)

    total_pnl = current_value - total_invested

    assigns =
      assigns
      |> assign(:total_invested, total_invested)
      |> assign(:current_value, current_value)
      |> assign(:total_pnl, total_pnl)

    ~H"""
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
      <.stat_card label="Open Positions" value={"#{length(@open_positions)}"} />
      <.stat_card label="Total Invested" value={"$#{format_price(@total_invested)}"} />
      <.stat_card label="Current Value" value={"$#{format_price(@current_value)}"} />
      <.stat_card
        label="Total P&L"
        value={"#{format_pnl(@total_pnl)}"}
        color={pnl_color(@total_pnl)}
      />
    </div>
    """
  end

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

  defp position_card(assigns) do
    group = assigns.group
    orders = Map.get(group, :dutch_orders, [])
    num_outcomes = length(orders)

    total_invested = Map.get(group, :total_invested, 0.0) || 0.0
    current_value = Map.get(group, :current_value, 0.0) || 0.0
    unrealized_pnl = current_value - total_invested
    pnl_pct = if total_invested > 0, do: unrealized_pnl / total_invested * 100, else: 0.0
    coverage = Map.get(group, :coverage, 0.0) || 0.0
    target_date = Map.get(group, :target_date)
    days_left = if target_date, do: days_until(target_date), else: nil
    station_code = Map.get(group, :station_code, "???")
    city = Map.get(group, :city, "")
    recommendation = Map.get(group, :sell_recommendation)

    # Sell vs hold data
    sell_value = current_value
    sell_profit = sell_value - total_invested
    sell_pct = if total_invested > 0, do: sell_profit / total_invested * 100, else: 0.0
    hold_payout = Map.get(group, :guaranteed_payout, 0.0) || 0.0
    hold_profit = hold_payout - total_invested
    hold_pct = if total_invested > 0, do: hold_profit / total_invested * 100, else: 0.0
    loss_chance = (1.0 - coverage) * 100

    # Progress bar width: capped at 100%
    progress_pct = if total_invested > 0, do: min(current_value / total_invested * 100, 150), else: 0

    assigns =
      assigns
      |> assign(:orders, orders)
      |> assign(:num_outcomes, num_outcomes)
      |> assign(:total_invested, total_invested)
      |> assign(:current_value, current_value)
      |> assign(:unrealized_pnl, unrealized_pnl)
      |> assign(:pnl_pct, pnl_pct)
      |> assign(:coverage, coverage)
      |> assign(:target_date, target_date)
      |> assign(:days_left, days_left)
      |> assign(:station_code, station_code)
      |> assign(:city, city)
      |> assign(:recommendation, recommendation)
      |> assign(:sell_value, sell_value)
      |> assign(:sell_profit, sell_profit)
      |> assign(:sell_pct, sell_pct)
      |> assign(:hold_payout, hold_payout)
      |> assign(:hold_profit, hold_profit)
      |> assign(:hold_pct, hold_pct)
      |> assign(:loss_chance, loss_chance)
      |> assign(:progress_pct, progress_pct)
      |> assign(:group_id, Map.get(group, :id))

    ~H"""
    <div class="p-4 space-y-4">
      <%!-- Card Header --%>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span class="font-mono text-lg font-bold text-zinc-900 dark:text-zinc-100">
            <%= @station_code %>
          </span>
          <span :if={@city != ""} class="text-sm text-zinc-500 dark:text-zinc-400"><%= @city %></span>
          <span :if={@target_date} class="text-xs text-zinc-400">
            <%= Calendar.strftime(@target_date, "%b %d, %Y") %>
          </span>
        </div>
        <span
          :if={@days_left}
          class={[
            "text-xs font-medium px-2 py-0.5 rounded-full",
            if(@days_left <= 1,
              do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400",
              else: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"
            )
          ]}
        >
          Resolves in <%= @days_left %>d
        </span>
      </div>

      <%!-- Strategy Label --%>
      <div class="text-xs text-zinc-500 dark:text-zinc-400">
        <span class="font-semibold text-indigo-600 dark:text-indigo-400">DUTCHING</span>
        (<%= @num_outcomes %> outcomes) | Coverage: <%= format_pct_raw(@coverage) %>
      </div>

      <%!-- Progress Bar --%>
      <div class="space-y-1">
        <div class="flex justify-between text-xs text-zinc-400">
          <span>Invested: $<%= format_price(@total_invested) %></span>
          <span>Current: $<%= format_price(@current_value) %></span>
        </div>
        <div class="w-full h-2 bg-zinc-200 dark:bg-zinc-700 rounded-full overflow-hidden">
          <div
            class={[
              "h-full rounded-full transition-all",
              if(@unrealized_pnl >= 0, do: "bg-green-500", else: "bg-red-500")
            ]}
            style={"width: #{min(@progress_pct, 100)}%"}
          />
        </div>
      </div>

      <%!-- Outcome Table --%>
      <div :if={@orders != []} class="overflow-x-auto">
        <table class="w-full text-xs">
          <thead>
            <tr class="border-b border-zinc-200 dark:border-zinc-700 text-left text-zinc-500 dark:text-zinc-400">
              <th class="px-2 py-1.5">Outcome</th>
              <th class="px-2 py-1.5 text-right">Buy Price</th>
              <th class="px-2 py-1.5 text-right">Current</th>
              <th class="px-2 py-1.5 text-right">Tokens</th>
              <th class="px-2 py-1.5 text-right">Value Now</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={order <- @orders} class="border-b border-zinc-100 dark:border-zinc-800">
              <td class="px-2 py-1.5 text-zinc-700 dark:text-zinc-300"><%= Map.get(order, :outcome_label, "-") %></td>
              <td class="px-2 py-1.5 text-right text-zinc-600 dark:text-zinc-400">
                $<%= format_price(Map.get(order, :buy_price, 0)) %>
              </td>
              <td class={"px-2 py-1.5 text-right font-medium #{price_change_color(Map.get(order, :buy_price, 0), Map.get(order, :current_price, 0))}"}>
                $<%= format_price(Map.get(order, :current_price, 0)) %>
                <%= price_arrow(Map.get(order, :buy_price, 0), Map.get(order, :current_price, 0)) %>
              </td>
              <td class="px-2 py-1.5 text-right text-zinc-600 dark:text-zinc-400">
                <%= format_price(Map.get(order, :tokens, 0)) %>
              </td>
              <td class="px-2 py-1.5 text-right text-zinc-600 dark:text-zinc-400">
                $<%= format_price((Map.get(order, :current_price, 0) || 0) * (Map.get(order, :tokens, 0) || 0)) %>
              </td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="border-t border-zinc-300 dark:border-zinc-600 font-semibold text-zinc-900 dark:text-zinc-100">
              <td class="px-2 py-1.5" colspan="3">Total</td>
              <td class="px-2 py-1.5 text-right">
                <%= format_price(Enum.reduce(@orders, 0.0, fn o, acc -> acc + (Map.get(o, :tokens, 0) || 0) end)) %>
              </td>
              <td class="px-2 py-1.5 text-right">$<%= format_price(@current_value) %></td>
            </tr>
          </tfoot>
        </table>
      </div>

      <%!-- Sell vs Hold Comparison --%>
      <div class="grid grid-cols-2 gap-3">
        <%!-- SELL NOW box --%>
        <div class={[
          "rounded-lg border p-3 space-y-2",
          if(@sell_profit >= @hold_profit,
            do: "border-green-300 dark:border-green-700 bg-green-50 dark:bg-green-900/20",
            else: "border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800"
          )
        ]}>
          <p class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase">Sell Now</p>
          <p class="text-lg font-bold text-zinc-900 dark:text-zinc-100">$<%= format_price(@sell_value) %></p>
          <p class={"text-sm font-medium #{pnl_color(@sell_profit)}"}>
            <%= format_pnl(@sell_profit) %> (<%= format_pct_raw(@sell_pct) %>)
          </p>
          <p class="text-xs text-zinc-400">Risk: NONE</p>
          <%= if @sell_profit >= @hold_profit do %>
            <button
              phx-click="request_sell"
              phx-value-group-id={@group_id}
              class="w-full mt-1 px-3 py-2 text-xs font-semibold rounded-lg bg-green-600 text-white hover:bg-green-700 transition-colors"
              disabled={@selling == @group_id}
            >
              <%= if @selling == @group_id, do: "Selling...", else: "SELL ALL" %>
            </button>
          <% else %>
            <button
              phx-click="request_sell"
              phx-value-group-id={@group_id}
              class="w-full mt-1 px-2 py-1 text-xs rounded-lg border border-zinc-300 dark:border-zinc-600 text-zinc-500 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-700 transition-colors"
              disabled={@selling == @group_id}
            >
              Sell
            </button>
          <% end %>
        </div>

        <%!-- HOLD box --%>
        <div class={[
          "rounded-lg border p-3 space-y-2",
          if(@hold_profit > @sell_profit,
            do: "border-green-300 dark:border-green-700 bg-green-50 dark:bg-green-900/20",
            else: "border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800"
          )
        ]}>
          <p class="text-xs font-semibold text-zinc-500 dark:text-zinc-400 uppercase">Hold</p>
          <p class="text-lg font-bold text-zinc-900 dark:text-zinc-100">$<%= format_price(@hold_payout) %></p>
          <p class={"text-sm font-medium #{pnl_color(@hold_profit)}"}>
            <%= format_pnl(@hold_profit) %> (<%= format_pct_raw(@hold_pct) %>)
          </p>
          <p class="text-xs text-zinc-400">
            Risk: <%= if @loss_chance > 0, do: "#{format_pct_raw(@loss_chance)} chance of loss", else: "NONE" %>
          </p>
          <div class={[
            "w-full mt-1 px-2 py-1 text-xs text-center rounded-lg",
            if(@hold_profit > @sell_profit,
              do: "bg-green-600 text-white font-semibold",
              else: "border border-zinc-300 dark:border-zinc-600 text-zinc-400"
            )
          ]}>
            HOLDING
          </div>
        </div>
      </div>

      <%!-- Recommendation Text --%>
      <div :if={@recommendation} class={[
        "text-sm font-medium px-3 py-2 rounded-lg",
        recommendation_style(@recommendation)
      ]}>
        <%= recommendation_text(@recommendation) %>
      </div>
    </div>
    """
  end

  defp sell_confirmation_modal(assigns) do
    group = assigns.group
    total_cost = Map.get(group, :total_invested, 0.0) || 0.0
    sell_value = Map.get(group, :current_value, 0.0) || 0.0
    profit = sell_value - total_cost
    station_code = Map.get(group, :station_code, "???")

    assigns =
      assigns
      |> assign(:total_cost, total_cost)
      |> assign(:sell_value, sell_value)
      |> assign(:profit, profit)
      |> assign(:station_code, station_code)
      |> assign(:group_id, Map.get(group, :id))

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="fixed inset-0 bg-black/40" phx-click="cancel_sell" />
      <div class="relative z-50 w-full max-w-md rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-6 shadow-xl space-y-4">
        <h3 class="text-lg font-bold text-zinc-900 dark:text-zinc-100">
          Confirm Sell — <%= @station_code %>
        </h3>

        <div class="space-y-2 text-sm">
          <div class="flex justify-between text-zinc-600 dark:text-zinc-400">
            <span>Estimated proceeds</span>
            <span class="font-medium text-zinc-900 dark:text-zinc-100">$<%= format_price(@sell_value) %></span>
          </div>
          <div class="flex justify-between text-zinc-600 dark:text-zinc-400">
            <span>Total cost</span>
            <span class="font-medium text-zinc-900 dark:text-zinc-100">$<%= format_price(@total_cost) %></span>
          </div>
          <div class="flex justify-between border-t border-zinc-200 dark:border-zinc-700 pt-2">
            <span class="font-medium text-zinc-700 dark:text-zinc-300">Profit</span>
            <span class={"font-bold #{pnl_color(@profit)}"}><%= format_pnl(@profit) %></span>
          </div>
        </div>

        <div class="rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 p-3">
          <p class="text-xs text-amber-700 dark:text-amber-400">
            Actual execution price may vary from estimates due to market movement and slippage.
          </p>
        </div>

        <div class="flex gap-3">
          <button
            phx-click="cancel_sell"
            class="flex-1 px-4 py-2 text-sm font-medium rounded-lg border border-zinc-300 dark:border-zinc-600 text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-zinc-800 transition-colors"
          >
            Cancel
          </button>
          <button
            phx-click="confirm_sell"
            phx-value-group-id={@group_id}
            class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg bg-red-600 text-white hover:bg-red-700 transition-colors"
          >
            Confirm Sell
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp history_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900">
      <button
        phx-click="toggle_history"
        class="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-zinc-800/50 transition-colors"
      >
        <span>Closed Positions (<%= length(@history) %>)</span>
        <span class="text-xs text-zinc-400"><%= if @history_expanded, do: "▲", else: "▼" %></span>
      </button>

      <div :if={@history_expanded} class="border-t border-zinc-200 dark:border-zinc-700">
        <div :if={@history == []} class="p-4 text-center text-sm text-zinc-400">
          No closed positions yet.
        </div>

        <div :if={@history != []} class="overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr class="border-b border-zinc-200 dark:border-zinc-700 text-left text-zinc-500 dark:text-zinc-400">
                <th class="px-3 py-2">Date</th>
                <th class="px-3 py-2">Station</th>
                <th class="px-3 py-2 text-right">Invested</th>
                <th class="px-3 py-2">Result</th>
                <th class="px-3 py-2 text-right">P&L</th>
                <th class="px-3 py-2">Exit Type</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={h <- @history} class="border-b border-zinc-100 dark:border-zinc-800">
                <td class="px-3 py-2 text-zinc-600 dark:text-zinc-400">
                  <%= format_date(Map.get(h, :closed_at) || Map.get(h, :target_date)) %>
                </td>
                <td class="px-3 py-2 font-mono font-semibold text-zinc-900 dark:text-zinc-100">
                  <%= Map.get(h, :station_code, "-") %>
                </td>
                <td class="px-3 py-2 text-right text-zinc-600 dark:text-zinc-400">
                  $<%= format_price(Map.get(h, :total_invested, 0)) %>
                </td>
                <td class="px-3 py-2">
                  <span class={["px-1.5 py-0.5 rounded text-xs font-medium", exit_result_class(Map.get(h, :status))]}>
                    <%= exit_result_label(Map.get(h, :status)) %>
                  </span>
                </td>
                <td class={"px-3 py-2 text-right font-semibold #{pnl_color(Map.get(h, :actual_pnl, 0))}"}>
                  <%= format_pnl(Map.get(h, :actual_pnl, 0)) %>
                </td>
                <td class="px-3 py-2 text-zinc-500 dark:text-zinc-400">
                  <%= exit_type_label(Map.get(h, :status)) %>
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr class="border-t border-zinc-300 dark:border-zinc-600 font-semibold text-zinc-900 dark:text-zinc-100">
                <td class="px-3 py-2" colspan="2">Total</td>
                <td class="px-3 py-2 text-right">
                  $<%= format_price(Enum.reduce(@history, 0.0, fn h, acc -> acc + (Map.get(h, :total_invested, 0) || 0) end)) %>
                </td>
                <td class="px-3 py-2"></td>
                <td class={"px-3 py-2 text-right font-bold #{pnl_color(Enum.reduce(@history, 0.0, fn h, acc -> acc + (Map.get(h, :actual_pnl, 0) || 0) end))}"}>
                  <%= format_pnl(Enum.reduce(@history, 0.0, fn h, acc -> acc + (Map.get(h, :actual_pnl, 0) || 0) end)) %>
                </td>
                <td class="px-3 py-2"></td>
              </tr>
            </tfoot>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp performance_stats_bar(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 text-center">
        <div>
          <div class={"text-xl font-bold #{pnl_color(@stats.total_pnl)}"}>
            <%= format_pnl(@stats.total_pnl) %>
          </div>
          <div class="text-xs text-zinc-500 dark:text-zinc-400">Total P&L</div>
        </div>
        <div>
          <div class="text-xl font-bold text-zinc-900 dark:text-zinc-100">
            <%= format_pct_raw(@stats.win_rate) %>
          </div>
          <div class="text-xs text-zinc-500 dark:text-zinc-400">Win Rate</div>
        </div>
        <div>
          <div class={"text-xl font-bold #{pnl_color(@stats.avg_profit)}"}>
            <%= format_pnl(@stats.avg_profit) %>
          </div>
          <div class="text-xs text-zinc-500 dark:text-zinc-400">Avg Profit</div>
        </div>
        <div>
          <div class="text-xl font-bold text-zinc-900 dark:text-zinc-100">
            <%= format_days(@stats.avg_hold_days) %>
          </div>
          <div class="text-xs text-zinc-500 dark:text-zinc-400">Avg Hold Days</div>
        </div>
      </div>
    </div>
    """
  end

  # ──────────────────────────────────────────────────────────
  # Event Handlers
  # ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("request_sell", %{"group-id" => id}, socket) do
    group = Enum.find(socket.assigns.open_positions, fn g -> to_string(Map.get(g, :id)) == id end)
    {:noreply, assign(socket, confirm_sell: group)}
  end

  @impl true
  def handle_event("confirm_sell", %{"group-id" => id}, socket) do
    socket = assign(socket, confirm_sell: nil, selling: id)

    Task.start(fn ->
      result = dutch_call(:sell_group, [id], {:error, "DutchGroups module not available"})

      Phoenix.PubSub.broadcast(
        WeatherEdge.PubSub,
        "dutch:sold",
        {:dutch_sold, id, result}
      )
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_sell", _params, socket) do
    {:noreply, assign(socket, confirm_sell: nil)}
  end

  @impl true
  def handle_event("toggle_history", _params, socket) do
    {:noreply, assign(socket, history_expanded: !socket.assigns.history_expanded)}
  end

  # Catch-all for events from dashboard_header (e.g. toggle_add_station_modal)
  @impl true
  def handle_event(_event, _params, socket) do
    {:noreply, socket}
  end

  # ──────────────────────────────────────────────────────────
  # PubSub Handlers
  # ──────────────────────────────────────────────────────────

  @impl true
  def handle_info({:dutch_price_update, group_id, updated_orders, recommendation}, socket) do
    open_positions =
      Enum.map(socket.assigns.open_positions, fn g ->
        if Map.get(g, :id) == group_id do
          current_value =
            Enum.reduce(updated_orders, 0.0, fn o, acc ->
              acc + (Map.get(o, :current_price, 0) || 0) * (Map.get(o, :tokens, 0) || 0)
            end)

          g
          |> Map.put(:dutch_orders, updated_orders)
          |> Map.put(:current_value, current_value)
          |> Map.put(:sell_recommendation, recommendation)
          |> Map.put(:sell_value, current_value)
        else
          g
        end
      end)

    {:noreply, assign(socket, open_positions: open_positions)}
  end

  @impl true
  def handle_info({:dutch_new_position, position}, socket) do
    {:noreply, assign(socket, open_positions: [position | socket.assigns.open_positions])}
  end

  @impl true
  def handle_info({:dutch_resolved, group_id, result}, socket) do
    resolved =
      Enum.find(socket.assigns.open_positions, fn g -> Map.get(g, :id) == group_id end)

    open = Enum.reject(socket.assigns.open_positions, fn g -> Map.get(g, :id) == group_id end)

    history =
      if resolved do
        entry =
          resolved
          |> Map.put(:status, Map.get(result, :status, "resolved"))
          |> Map.put(:actual_pnl, Map.get(result, :actual_pnl, 0))
          |> Map.put(:exit_type, "resolved")

        [entry | socket.assigns.history]
      else
        socket.assigns.history
      end

    stats = dutch_call(:compute_performance_stats, [], socket.assigns.stats)

    {:noreply, assign(socket, open_positions: open, history: history, stats: stats, selling: nil)}
  end

  @impl true
  def handle_info({:dutch_sold, group_id, result}, socket) do
    sold = Enum.find(socket.assigns.open_positions, fn g -> Map.get(g, :id) == group_id end)
    open = Enum.reject(socket.assigns.open_positions, fn g -> Map.get(g, :id) == group_id end)

    history =
      if sold do
        pnl =
          case result do
            {:ok, r} -> Map.get(r, :actual_pnl, 0)
            _ -> 0
          end

        entry =
          sold
          |> Map.put(:status, "sold")
          |> Map.put(:realized_pnl, pnl)
          |> Map.put(:exit_type, "sold")

        [entry | socket.assigns.history]
      else
        socket.assigns.history
      end

    stats = dutch_call(:compute_performance_stats, [], socket.assigns.stats)

    {:noreply, assign(socket, open_positions: open, history: history, stats: stats, selling: nil)}
  end

  @impl true
  def handle_info({:sell_progress, group_id, progress}, socket) do
    if socket.assigns.selling == group_id do
      {:noreply, assign(socket, sell_progress: progress)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:balance_updated, balance}, socket) do
    {:noreply, assign(socket, balance: balance)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ──────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────

  @dutch_groups_module WeatherEdge.Trading.DutchGroups

  defp dutch_call(func, args, default) do
    if Code.ensure_loaded?(@dutch_groups_module) &&
         function_exported?(@dutch_groups_module, func, length(args)) do
      apply(@dutch_groups_module, func, args)
    else
      default
    end
  rescue
    _e -> default
  end

  defp default_stats do
    %{total_pnl: 0.0, win_rate: 0.0, avg_profit: 0.0, avg_hold_days: 0.0}
  end

  defp format_price(nil), do: "0.00"
  defp format_price(val) when is_number(val), do: :erlang.float_to_binary(val * 1.0, decimals: 2)
  defp format_price(_), do: "0.00"

  defp format_pnl(nil), do: "$0.00"

  defp format_pnl(val) when is_number(val) do
    sign = if val >= 0, do: "+", else: "-"
    "$#{sign}#{:erlang.float_to_binary(abs(val * 1.0), decimals: 2)}"
  end

  defp format_pnl(_), do: "$0.00"

  defp format_pct_raw(nil), do: "0.0%"

  defp format_pct_raw(val) when is_number(val) do
    "#{:erlang.float_to_binary(val * 1.0, decimals: 1)}%"
  end

  defp format_pct_raw(_), do: "0.0%"

  defp format_days(nil), do: "-"
  defp format_days(val) when is_number(val), do: "#{:erlang.float_to_binary(val * 1.0, decimals: 1)}d"
  defp format_days(_), do: "-"

  defp format_date(nil), do: "-"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %d")
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d %H:%M")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d %H:%M")
  defp format_date(_), do: "-"

  defp days_until(%Date{} = target_date), do: Date.diff(target_date, Date.utc_today())
  defp days_until(_), do: nil

  defp pnl_color(nil), do: "text-zinc-500"
  defp pnl_color(val) when is_number(val) and val > 0, do: "text-green-600"
  defp pnl_color(val) when is_number(val) and val < 0, do: "text-red-600"
  defp pnl_color(_), do: "text-zinc-500 dark:text-zinc-400"

  defp price_change_color(buy, current) when is_number(buy) and is_number(current) do
    cond do
      current > buy -> "text-green-600"
      current < buy -> "text-red-600"
      true -> "text-zinc-600 dark:text-zinc-400"
    end
  end

  defp price_change_color(_, _), do: "text-zinc-600 dark:text-zinc-400"

  defp price_arrow(buy, current) when is_number(buy) and is_number(current) do
    cond do
      current > buy -> "↑"
      current < buy -> "↓"
      true -> ""
    end
  end

  defp price_arrow(_, _), do: ""

  defp recommendation_style(rec) do
    action = Map.get(rec, :action, :hold)

    case action do
      :sell_urgent -> "bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-400 border border-red-200 dark:border-red-800"
      :sell_now -> "bg-amber-50 dark:bg-amber-900/20 text-amber-700 dark:text-amber-400 border border-amber-200 dark:border-amber-800"
      :hold -> "bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-400 border border-green-200 dark:border-green-800"
      _ -> "bg-zinc-50 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400 border border-zinc-200 dark:border-zinc-700"
    end
  end

  defp recommendation_text(rec) when is_map(rec) do
    Map.get(rec, :message, Map.get(rec, :reason, "No recommendation available"))
  end

  defp recommendation_text(_), do: "No recommendation available"

  defp exit_result_class("won"), do: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
  defp exit_result_class("resolved_win"), do: "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
  defp exit_result_class("lost"), do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
  defp exit_result_class("resolved_loss"), do: "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
  defp exit_result_class("sold"), do: "bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400"
  defp exit_result_class(_), do: "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"

  defp exit_result_label("won"), do: "WIN"
  defp exit_result_label("resolved_win"), do: "WIN"
  defp exit_result_label("lost"), do: "LOSS"
  defp exit_result_label("resolved_loss"), do: "LOSS"
  defp exit_result_label("sold"), do: "SOLD"
  defp exit_result_label(nil), do: "-"
  defp exit_result_label(s) when is_binary(s), do: String.upcase(s)
  defp exit_result_label(_), do: "-"

  defp exit_type_label("won"), do: "Resolution (Win)"
  defp exit_type_label("lost"), do: "Resolution (Loss)"
  defp exit_type_label("sold"), do: "Manual Sell"
  defp exit_type_label(nil), do: "-"
  defp exit_type_label(s) when is_binary(s), do: String.capitalize(s)
  defp exit_type_label(_), do: "-"
end
