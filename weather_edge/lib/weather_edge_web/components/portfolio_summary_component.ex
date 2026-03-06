defmodule WeatherEdgeWeb.Components.PortfolioSummaryComponent do
  use Phoenix.Component

  attr :positions, :list, required: true
  attr :sidecar_positions, :list, default: []
  attr :balance, :float, default: nil

  def portfolio_summary(assigns) do
    {open_count, total_invested, current_value, unrealized_pnl, unrealized_pnl_pct,
     today_realized, total_realized} =
      if assigns.sidecar_positions != [] do
        # Use sidecar for open position data, but DB for realized P&L
        {oc, ti, cv, up, upp, _tr_sidecar, _tr_sidecar2} =
          compute_from_sidecar(assigns.sidecar_positions)

        {today_r, total_r} = compute_realized_from_db(assigns.positions)
        {oc, ti, cv, up, upp, today_r, total_r}
      else
        compute_from_db(assigns.positions)
      end

    assigns =
      assigns
      |> assign(:open_count, open_count)
      |> assign(:total_invested, total_invested)
      |> assign(:current_value, current_value)
      |> assign(:unrealized_pnl, unrealized_pnl)
      |> assign(:unrealized_pnl_pct, unrealized_pnl_pct)
      |> assign(:today_realized, today_realized)
      |> assign(:total_realized, total_realized)

    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-4">
      <h3 class="text-sm font-semibold text-zinc-600 mb-3">Portfolio Summary</h3>
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4">
        <div>
          <p class="text-xs text-zinc-400">Open Positions</p>
          <p class="text-lg font-semibold text-zinc-900"><%= @open_count %></p>
        </div>
        <div>
          <p class="text-xs text-zinc-400">Total Invested</p>
          <p class="text-lg font-semibold text-zinc-900">$<%= format_usd(@total_invested) %></p>
        </div>
        <div>
          <p class="text-xs text-zinc-400">Current Value</p>
          <p class="text-lg font-semibold text-zinc-900">$<%= format_usd(@current_value) %></p>
        </div>
        <div>
          <p class="text-xs text-zinc-400">Unrealized P&L</p>
          <p class={"text-lg font-semibold #{pnl_color(@unrealized_pnl)}"}>
            <%= pnl_sign(@unrealized_pnl) %><%= format_usd(abs(@unrealized_pnl)) %>
            <span class="text-xs">(<%= pnl_sign(@unrealized_pnl_pct) %><%= :erlang.float_to_binary(abs(@unrealized_pnl_pct), decimals: 1) %>%)</span>
          </p>
        </div>
        <div>
          <p class="text-xs text-zinc-400">Today's Realized</p>
          <p class={"text-lg font-semibold #{pnl_color(@today_realized)}"}>
            <%= pnl_sign(@today_realized) %><%= format_usd(abs(@today_realized)) %>
          </p>
        </div>
        <div>
          <p class="text-xs text-zinc-400">Total Realized</p>
          <p class={"text-lg font-semibold #{pnl_color(@total_realized)}"}>
            <%= pnl_sign(@total_realized) %><%= format_usd(abs(@total_realized)) %>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp compute_from_sidecar(positions) do
    open_count = length(positions)

    total_invested =
      Enum.reduce(positions, 0.0, fn p, acc ->
        acc + to_float(p["initialValue"])
      end)

    current_value =
      Enum.reduce(positions, 0.0, fn p, acc ->
        acc + to_float(p["currentValue"])
      end)

    unrealized_pnl =
      Enum.reduce(positions, 0.0, fn p, acc ->
        acc + to_float(p["cashPnl"])
      end)

    unrealized_pnl_pct =
      if total_invested > 0, do: unrealized_pnl / total_invested * 100, else: 0.0

    total_realized =
      Enum.reduce(positions, 0.0, fn p, acc ->
        acc + to_float(p["realizedPnl"])
      end)

    {open_count, total_invested, current_value, unrealized_pnl, unrealized_pnl_pct, total_realized,
     total_realized}
  end

  defp compute_realized_from_db(positions) do
    closed_positions = Enum.filter(positions, &(&1.status != "open"))
    today = Date.utc_today()

    today_realized =
      closed_positions
      |> Enum.filter(fn p -> p.closed_at && DateTime.to_date(p.closed_at) == today end)
      |> Enum.reduce(0.0, fn p, acc -> acc + (p.realized_pnl || 0.0) end)

    total_realized =
      Enum.reduce(closed_positions, 0.0, fn p, acc -> acc + (p.realized_pnl || 0.0) end)

    {today_realized, total_realized}
  end

  defp compute_from_db(positions) do
    open_positions = Enum.filter(positions, &(&1.status == "open"))
    closed_positions = Enum.filter(positions, &(&1.status != "open"))

    open_count = length(open_positions)
    total_invested = Enum.reduce(open_positions, 0.0, &(&1.total_cost_usdc + &2))

    current_value =
      Enum.reduce(open_positions, 0.0, fn p, acc ->
        price = p.current_price || p.avg_buy_price
        acc + price * p.tokens
      end)

    unrealized_pnl = current_value - total_invested

    unrealized_pnl_pct =
      if total_invested > 0, do: unrealized_pnl / total_invested * 100, else: 0.0

    today = Date.utc_today()

    today_realized =
      closed_positions
      |> Enum.filter(fn p -> p.closed_at && DateTime.to_date(p.closed_at) == today end)
      |> Enum.reduce(0.0, fn p, acc -> acc + (p.realized_pnl || 0.0) end)

    total_realized =
      Enum.reduce(closed_positions, 0.0, fn p, acc -> acc + (p.realized_pnl || 0.0) end)

    {open_count, total_invested, current_value, unrealized_pnl, unrealized_pnl_pct,
     today_realized, total_realized}
  end

  defp to_float(nil), do: 0.0
  defp to_float(val) when is_float(val), do: val
  defp to_float(val) when is_integer(val), do: val / 1
  defp to_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp format_usd(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 2)
  end

  defp pnl_color(value) when value > 0, do: "text-green-600"
  defp pnl_color(value) when value < 0, do: "text-red-600"
  defp pnl_color(_), do: "text-zinc-600"

  defp pnl_sign(value) when value > 0, do: "+"
  defp pnl_sign(value) when value < 0, do: "-"
  defp pnl_sign(_), do: ""
end
