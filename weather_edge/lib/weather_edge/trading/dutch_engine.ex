defmodule WeatherEdge.Trading.DutchEngine do
  @moduledoc """
  Core dutching math. Pure functions, no side effects.
  Selects outcomes, computes allocations, and evaluates exit strategies.
  """

  defstruct [:outcomes, :sum_prices, :profit_pct, :coverage, :is_profitable]

  @doc """
  Select which outcomes to include in the dutch bet.
  Greedily adds outcomes sorted by model probability while respecting constraints.
  """
  def select_outcomes(cluster_outcomes, distribution, live_prices, config) do
    max_sum = Map.get(config, :dutch_max_sum, 0.85)
    min_coverage = Map.get(config, :dutch_min_coverage, 0.70)
    max_outcomes = Map.get(config, :dutch_max_outcomes, 5)

    # Build candidate list with model_prob and live_price
    candidates =
      cluster_outcomes
      |> Enum.map(fn o ->
        label = o["outcome_label"] || o["label"]
        model_prob = get_model_prob(distribution, label)
        price = Map.get(live_prices, label, o["yes_price"] || 0)
        token_id = extract_token_id(o)

        %{
          outcome_label: label,
          model_prob: model_prob,
          price: price,
          token_id: token_id,
          raw: o
        }
      end)
      |> Enum.filter(fn c -> c.model_prob >= 0.02 and c.price > 0 and c.price < 0.50 end)
      |> Enum.sort_by(& &1.model_prob, :desc)

    # Greedily select outcomes
    {selected, sum, cov} =
      Enum.reduce_while(candidates, {[], 0.0, 0.0}, fn candidate, {sel, sum_acc, cov_acc} ->
        new_sum = sum_acc + candidate.price
        new_cov = cov_acc + candidate.model_prob

        cond do
          length(sel) >= max_outcomes -> {:halt, {sel, sum_acc, cov_acc}}
          new_sum > max_sum -> {:halt, {sel, sum_acc, cov_acc}}
          true -> {:cont, {sel ++ [candidate], new_sum, new_cov}}
        end
      end)

    # If coverage too low, try adding one more if possible
    {selected, sum, cov} =
      if cov < min_coverage do
        remaining = Enum.reject(candidates, fn c -> c in selected end)

        case remaining do
          [next | _] when length(selected) < max_outcomes ->
            {selected ++ [next], sum + next.price, cov + next.model_prob}

          _ ->
            {selected, sum, cov}
        end
      else
        {selected, sum, cov}
      end

    %__MODULE__{
      outcomes: selected,
      sum_prices: sum,
      profit_pct: if(sum > 0, do: 1.0 / sum - 1.0, else: 0.0),
      coverage: cov,
      is_profitable: sum > 0 and sum < 1.0
    }
  end

  @doc """
  Compute dollar allocation per outcome for equal payout (dutching formula).
  tokens_per_outcome = budget / sum_prices
  Each outcome gets: invested = price * tokens, tokens = tokens_per_outcome
  """
  def compute_allocation(%__MODULE__{outcomes: outcomes, sum_prices: sum} = _selection, budget)
      when sum > 0 do
    tokens_per_outcome = budget / sum

    orders =
      Enum.map(outcomes, fn o ->
        invested = o.price * tokens_per_outcome

        %{
          outcome_label: o.outcome_label,
          token_id: o.token_id,
          buy_price: o.price,
          tokens: tokens_per_outcome,
          invested: invested
        }
      end)

    guaranteed_payout = tokens_per_outcome
    profit_usd = guaranteed_payout - budget

    %{
      orders: orders,
      total_invested: budget,
      guaranteed_payout: guaranteed_payout,
      profit_pct: 1.0 / sum - 1.0,
      profit_usd: profit_usd
    }
  end

  def compute_allocation(_, _budget), do: nil

  @doc """
  Compute current total value of a dutch group at current market prices.
  """
  def compute_current_value(dutch_orders, current_prices) do
    Enum.reduce(dutch_orders, 0.0, fn order, acc ->
      label = order.outcome_label
      price = Map.get(current_prices, label, order.current_price || order.buy_price)
      acc + order.tokens * price
    end)
  end

  @doc """
  Compare selling now vs holding to resolution.
  """
  def compare_exit_strategies(dutch_group, dutch_orders, current_prices, _forecast) do
    current_value = compute_current_value(dutch_orders, current_prices)
    sell_profit = current_value - dutch_group.total_invested
    sell_profit_pct = if dutch_group.total_invested > 0, do: sell_profit / dutch_group.total_invested, else: 0.0
    hold_profit = dutch_group.guaranteed_payout - dutch_group.total_invested
    hold_profit_pct = dutch_group.guaranteed_profit_pct
    loss_risk = 1.0 - dutch_group.coverage

    %{
      sell_now: %{value: current_value, profit: sell_profit, profit_pct: sell_profit_pct, risk: "none"},
      hold_to_resolution: %{value: dutch_group.guaranteed_payout, profit: hold_profit, profit_pct: hold_profit_pct, risk: "#{Float.round(loss_risk * 100, 1)}% chance of total loss"},
      better_option: if(current_value > dutch_group.guaranteed_payout, do: :sell, else: :hold)
    }
  end

  defp get_model_prob(distribution, label) do
    case distribution do
      %{probabilities: probs} -> Map.get(probs, label, 0.0)
      _ -> 0.0
    end
  end

  defp extract_token_id(%{"clob_token_ids" => [id | _]}), do: strip_quotes(id)
  defp extract_token_id(%{"clob_token_ids" => id}) when is_binary(id), do: strip_quotes(id)
  defp extract_token_id(%{"token_id" => id}), do: strip_quotes(id)
  defp extract_token_id(_), do: nil

  defp strip_quotes(s) when is_binary(s), do: String.replace(s, "\"", "")
  defp strip_quotes(s), do: s
end
