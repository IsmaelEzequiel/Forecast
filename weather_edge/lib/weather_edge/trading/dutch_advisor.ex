defmodule WeatherEdge.Trading.DutchAdvisor do
  @moduledoc """
  Generates sell/hold recommendations for open dutch positions.
  """

  alias WeatherEdge.Trading.DutchEngine

  def recommend(dutch_group, dutch_orders, current_prices, latest_forecast) do
    current_value = DutchEngine.compute_current_value(dutch_orders, current_prices)
    sell_profit = current_value - dutch_group.total_invested
    sell_profit_pct = if dutch_group.total_invested > 0, do: sell_profit / dutch_group.total_invested, else: 0.0
    hold_profit = dutch_group.guaranteed_payout - dutch_group.total_invested
    hold_profit_pct = dutch_group.guaranteed_profit_pct
    days_left = Date.diff(dutch_group.target_date, Date.utc_today())
    forecast_in_range = forecast_covered?(latest_forecast, dutch_group, dutch_orders)
    loss_risk = "#{Float.round((1.0 - dutch_group.coverage) * 100, 1)}% chance of loss"

    base = %{
      sell_value: current_value,
      sell_profit: sell_profit,
      sell_profit_pct: sell_profit_pct,
      hold_value: dutch_group.guaranteed_payout,
      hold_profit: hold_profit,
      hold_risk: loss_risk
    }

    cond do
      # Forecast shifted OUTSIDE covered range and resolving soon
      not forecast_in_range and days_left <= 1 ->
        Map.merge(base, %{
          action: :sell_urgent,
          reason: "Forecast shifted outside covered temperatures. Sell NOW to keep #{format_pct(sell_profit_pct)} profit."
        })

      # Current value exceeds guaranteed payout
      current_value > dutch_group.guaranteed_payout * 1.05 ->
        Map.merge(base, %{
          action: :sell_now,
          reason: "Selling now gives #{format_money(sell_profit)} (#{format_pct(sell_profit_pct)}) — MORE than holding (#{format_money(hold_profit)}). Zero risk."
        })

      # Resolution today, forecast in range
      days_left == 0 and forecast_in_range ->
        Map.merge(base, %{
          action: :hold,
          reason: "Resolves today. Forecast in covered range. Hold for guaranteed #{format_money(hold_profit)} (#{format_pct(hold_profit_pct)})."
        })

      # Resolution tomorrow, good profit already
      days_left == 1 and sell_profit_pct > 0.3 ->
        Map.merge(base, %{
          action: :consider_sell,
          reason: "#{format_pct(sell_profit_pct)} profit now. Resolution tomorrow — lock in or wait for guaranteed #{format_pct(hold_profit_pct)}."
        })

      # Default: hold
      true ->
        Map.merge(base, %{
          action: :hold,
          reason: "Position healthy. #{days_left} days to resolution. Current value: #{format_money(current_value)}."
        })
    end
  end

  defp forecast_covered?(nil, _group, _orders), do: true

  defp forecast_covered?(distribution, _group, dutch_orders) do
    case distribution do
      %{probabilities: probs} when map_size(probs) > 0 ->
        {top_label, _prob} = Enum.max_by(probs, fn {_l, p} -> p end)
        covered_labels = Enum.map(dutch_orders, & &1.outcome_label)
        top_label in covered_labels

      _ ->
        true
    end
  end

  defp format_pct(val) when is_number(val), do: "#{Float.round(val * 100, 1)}%"
  defp format_pct(_), do: "-"

  defp format_money(val) when is_number(val) do
    sign = if val >= 0, do: "+$", else: "-$"
    "#{sign}#{:erlang.float_to_binary(abs(val), decimals: 2)}"
  end

  defp format_money(_), do: "$0.00"
end
