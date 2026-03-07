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
          confidence: String.t(),
          liquidity: float()
        }

  @doc """
  Detects mispricings by comparing a probability distribution to market prices.

  Options:
    - `:observed_high_c` — today's observed high temperature in Celsius.
      When provided, outcomes that are already determined by the observed temp
      are skipped (e.g., won't recommend BUY NO on 27°C when observed high is already 27°C).

  Returns `{:ok, signals, flags}` where signals is a list of detected opportunities
  and flags contains structural information (e.g., `:structural_mispricing`).
  """
  @spec detect_mispricings(MarketCluster.t(), Distribution.t(), keyword()) ::
          {:ok, [signal()], [atom()]}
  def detect_mispricings(%MarketCluster{outcomes: outcomes} = cluster, %Distribution{} = dist, opts \\ [])
      when is_list(outcomes) do
    # If any outcome has YES price >= 0.95, the market is effectively resolved — skip entirely
    if cluster_resolved?(outcomes) do
      {:ok, [], [:cluster_resolved]}
    else
      flags = check_structural_mispricing(outcomes)
      observed_high_c = Keyword.get(opts, :observed_high_c)
      confidence = Keyword.get(opts, :confidence, "forecast")

      signals =
        outcomes
        |> Enum.map(fn outcome -> analyze_outcome(outcome, dist, observed_high_c, cluster, confidence) end)
        |> Enum.filter(fn signal -> signal != nil end)

      {:ok, signals, flags}
    end
  end

  defp cluster_resolved?(outcomes) do
    Enum.any?(outcomes, fn o ->
      yes_price = Map.get(o, "yes_price", 0.0)
      is_number(yes_price) and yes_price >= 0.95
    end)
  end

  defp analyze_outcome(outcome, dist, observed_high_c, cluster, confidence) do
    label = Map.get(outcome, "outcome_label", "")
    yes_price = Map.get(outcome, "yes_price", 0.0)
    no_price = Map.get(outcome, "no_price", 0.0)
    liquidity = Map.get(outcome, "liquidity", 0.0)

    # Skip outcomes that are effectively settled:
    # market at 95%+ YES = already resolved on Polymarket, don't fight it
    if yes_price >= 0.95 do
      nil
    else
      # Try exact match first, then extract short temp label (e.g., "28C" from full question)
      short_label = extract_temp_label(label)

      # If we have an observed high for today, use it to determine already-settled outcomes
      model_prob =
        case observed_override(short_label, observed_high_c, cluster) do
          {:resolved, prob} -> prob
          :use_model -> Distribution.probability_for(dist, short_label)
        end

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
          confidence: confidence,
          liquidity: liquidity
        }
      end
    end
  end

  # When observed high is available (today's market), override model probability
  # for outcomes that are already determined by observation.
  defp observed_override(_label, nil, _cluster), do: :use_model

  defp observed_override(label, observed_high_c, _cluster) when is_number(observed_high_c) do
    case parse_outcome_temp(label) do
      {:or_higher, temp, unit} ->
        observed = convert_temp(observed_high_c, unit)
        # "X or higher" is already YES if observed >= X
        if observed >= temp, do: {:resolved, 1.0}, else: :use_model

      {:or_below, temp, unit} ->
        observed = convert_temp(observed_high_c, unit)
        # "X or below" — can only be YES if final high <= X.
        # If observed already > X, it's resolved NO.
        if observed > temp, do: {:resolved, 0.0}, else: :use_model

      {:exact, temp, unit} ->
        observed = convert_temp(observed_high_c, unit)
        cond do
          # Observed is exactly this temp — likely the winning outcome
          observed == temp -> {:resolved, 1.0}
          # Observed already exceeded — can't be this temp anymore
          observed > temp -> {:resolved, 0.0}
          # Observed below — temp could still rise to this value
          true -> :use_model
        end

      {:range, low, high, unit} ->
        observed = convert_temp(observed_high_c, unit)
        cond do
          # Observed is within the range — this is the likely winner
          observed >= low and observed <= high -> {:resolved, 1.0}
          # Observed already above the range — high exceeded it
          observed > high -> {:resolved, 0.0}
          # Observed below range — temp could still rise into it
          true -> :use_model
        end

      :unknown ->
        :use_model
    end
  end

  defp parse_outcome_temp(label) do
    cond do
      match = Regex.run(~r/^(-?\d+)\s*([CF])\s+or higher$/i, label) ->
        [_, temp, unit] = match
        {:or_higher, String.to_integer(temp), String.upcase(unit)}

      match = Regex.run(~r/^(-?\d+)\s*([CF])\s+or below$/i, label) ->
        [_, temp, unit] = match
        {:or_below, String.to_integer(temp), String.upcase(unit)}

      match = Regex.run(~r/^(-?\d+)\s*-\s*(-?\d+)\s*([CF])$/i, label) ->
        [_, low, high, unit] = match
        {:range, String.to_integer(low), String.to_integer(high), String.upcase(unit)}

      match = Regex.run(~r/^(-?\d+)\s*([CF])$/i, label) ->
        [_, temp, unit] = match
        {:exact, String.to_integer(temp), String.upcase(unit)}

      true ->
        :unknown
    end
  end

  defp convert_temp(temp_c, "C"), do: round(temp_c)
  defp convert_temp(temp_c, "F"), do: round(temp_c * 9 / 5 + 32)
  defp convert_temp(temp_c, _), do: round(temp_c)

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
