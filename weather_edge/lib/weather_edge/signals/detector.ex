defmodule WeatherEdge.Signals.Detector do
  @moduledoc """
  Mispricing detection engine. Compares forecast probability distributions
  to market prices and generates trading signals.
  """

  alias WeatherEdge.Markets.MarketCluster
  alias WeatherEdge.Probability.Distribution

  @type signal :: %{
          outcome_label: String.t(),
          model_probability: float(),
          market_yes_price: float(),
          market_no_price: float(),
          edge: float(),
          recommended_side: String.t(),
          alert_level: String.t() | nil,
          liquidity: float()
        }

  @doc """
  Detects mispricings by comparing a probability distribution to market prices.

  Returns `{:ok, signals, flags}` where signals is a list of detected opportunities
  and flags contains structural information (e.g., `:structural_mispricing`).
  """
  @spec detect_mispricings(MarketCluster.t(), Distribution.t()) ::
          {:ok, [signal()], [atom()]}
  def detect_mispricings(%MarketCluster{outcomes: outcomes}, %Distribution{} = dist)
      when is_list(outcomes) do
    flags = check_structural_mispricing(outcomes)

    signals =
      outcomes
      |> Enum.map(fn outcome -> analyze_outcome(outcome, dist) end)
      |> Enum.filter(fn signal -> signal != nil end)

    {:ok, signals, flags}
  end

  defp analyze_outcome(outcome, dist) do
    label = Map.get(outcome, "outcome_label", "")
    yes_price = Map.get(outcome, "yes_price", 0.0)
    no_price = Map.get(outcome, "no_price", 0.0)
    liquidity = Map.get(outcome, "liquidity", 0.0)

    # Try exact match first, then extract short temp label (e.g., "28C" from full question)
    short_label = extract_temp_label(label)
    model_prob = Distribution.probability_for(dist, short_label)

    edge_yes = model_prob - yes_price
    edge_no = (1.0 - model_prob) - no_price

    {edge, side} = pick_best_side(edge_yes, edge_no)

    market_price = if side == "YES", do: yes_price, else: no_price

    alert_level = determine_alert_level(model_prob, edge, liquidity, market_price, side)

    if alert_level do
      %{
        outcome_label: label,
        model_probability: model_prob,
        market_yes_price: yes_price,
        market_no_price: no_price,
        edge: edge,
        recommended_side: side,
        alert_level: alert_level,
        liquidity: liquidity
      }
    end
  end

  defp pick_best_side(edge_yes, edge_no) do
    cond do
      edge_yes >= edge_no and edge_yes > 0 -> {edge_yes, "YES"}
      edge_no > 0 -> {edge_no, "NO"}
      edge_yes > edge_no -> {edge_yes, "YES"}
      true -> {edge_no, "NO"}
    end
  end

  defp determine_alert_level(model_prob, edge, liquidity, market_no_price, side) do
    cond do
      model_prob < 0.05 and side == "NO" and market_no_price <= 0.92 ->
        "safe_no"

      edge >= 0.25 ->
        "extreme"

      edge >= 0.15 and liquidity > 20.0 ->
        "strong"

      edge >= 0.08 and liquidity > 20.0 ->
        "opportunity"

      true ->
        nil
    end
  end

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

  defp extract_temp_label(label), do: label

  defp check_structural_mispricing(outcomes) do
    yes_sum =
      outcomes
      |> Enum.map(fn o -> Map.get(o, "yes_price", 0.0) end)
      |> Enum.sum()

    if abs(yes_sum - 1.0) > 0.05 do
      [:structural_mispricing]
    else
      []
    end
  end
end
