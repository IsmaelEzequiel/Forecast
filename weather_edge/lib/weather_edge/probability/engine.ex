defmodule WeatherEdge.Probability.Engine do
  @moduledoc """
  Probability engine that combines multi-model forecasts into a
  probability distribution across temperature outcomes.

  Supports accuracy-weighted ensemble: models with lower historical MAE
  get higher weight in the distribution. Falls back to equal weighting
  when no accuracy data is available.
  """

  require Logger

  alias WeatherEdge.Forecasts
  alias WeatherEdge.Forecasts.MetarClient
  alias WeatherEdge.Probability.{Distribution, Gaussian}
  alias WeatherEdge.Calibration.BiasTracker
  alias WeatherEdge.Timezone.PeakCalculator

  @doc """
  Computes a probability distribution for temperature outcomes given a station and target date.

  1. Fetches the latest forecast snapshot per model
  2. Weights each model by inverse MAE (if accuracy data exists)
  3. Builds weighted empirical distribution
  4. Applies Gaussian smoothing
  5. Collapses tails into edge buckets
  6. Normalizes to sum = 1.0
  """
  @spec compute_distribution(String.t(), Date.t(), keyword()) :: {:ok, Distribution.t()} | {:error, term()}
  def compute_distribution(station_code, target_date, opts \\ []) do
    snapshots = Forecasts.latest_snapshots(station_code, target_date)

    if snapshots == [] do
      {:error, :no_forecasts}
    else
      days_out = Date.diff(target_date, Date.utc_today())
      sigma = Gaussian.sigma(max(days_out, 0))

      lower_bound = Keyword.get(opts, :lower_bound)
      upper_bound = Keyword.get(opts, :upper_bound)
      unit = Keyword.get(opts, :temp_unit, "C")

      model_weights = compute_model_weights(station_code)

      empirical =
        snapshots
        |> extract_temps(unit)
        |> build_weighted_empirical(snapshots, model_weights)

      # For today's markets, inject observed temperature from METAR as a high-confidence data point.
      # When the observed temp already exceeds model predictions, the models are wrong —
      # the observation should dominate the distribution.
      empirical =
        if days_out == 0 do
          inject_observed_temperature(empirical, station_code, unit)
        else
          empirical
        end

      distribution =
        empirical
        |> Gaussian.apply_kernel(sigma)
        |> collapse_tails(lower_bound, upper_bound, unit)
        |> to_distribution()

      {:ok, distribution}
    end
  end

  # Injects the observed METAR temperature into the empirical distribution.
  # Weight depends on peak status:
  # - post_peak/night: observed IS the final answer, always inject with 60% weight
  # - near_peak: inject with 40% weight, but only if observed >= model mean
  #   (temp may still rise slightly, so a lower reading is not yet meaningful)
  # - pre_peak: SKIP injection entirely. Morning temps are just current readings,
  #   not daily highs. Injecting them creates false signals (e.g. 9°C at 77% when
  #   forecast high is 13°C).
  defp inject_observed_temperature(empirical, station_code, unit) do
    with {:ok, observed_high_c} <- MetarClient.get_todays_high(station_code) do
      observed_temp = if unit == "F", do: round(observed_high_c * 9 / 5 + 32), else: round(observed_high_c)

      # Look up station longitude for peak calculation
      station_longitude = get_station_longitude(station_code)
      {peak_status, _hours} = PeakCalculator.peak_status(station_longitude)

      # Calculate model consensus (weighted mean temperature)
      model_mean =
        Enum.reduce(empirical, 0.0, fn {temp, prob}, acc -> acc + temp * prob end)

      case peak_status do
        status when status in [:post_peak, :night] ->
          # Day is over — observed high is definitive, always inject
          do_inject(empirical, observed_temp, 0.60)

        :near_peak when observed_temp >= model_mean ->
          # Near peak and observed already meets/exceeds forecast — inject
          do_inject(empirical, observed_temp, 0.40)

        _ ->
          # Pre-peak or near-peak with observed below forecast — skip
          Logger.debug(
            "Engine: Skipping METAR injection for #{station_code} " <>
              "(#{peak_status}, observed=#{observed_temp}, model_mean=#{round(model_mean)})"
          )
          empirical
      end
    else
      _ ->
        Logger.debug("Engine: No METAR data for #{station_code}, using models only")
        empirical
    end
  end

  defp do_inject(empirical, observed_temp, weight) do
    model_scale = 1.0 - weight
    scaled = Map.new(empirical, fn {temp, prob} -> {temp, prob * model_scale} end)
    Map.update(scaled, observed_temp, weight, &(&1 + weight))
  end

  defp get_station_longitude(station_code) do
    case WeatherEdge.Stations.get_by_code(station_code) do
      {:ok, station} -> station.longitude
      _ -> 0.0
    end
  end

  defp compute_model_weights(station_code) do
    stats = BiasTracker.stats_for_station(station_code)

    case stats do
      %{count: count, model_stats: model_stats} when count >= 3 and map_size(model_stats) > 0 ->
        # Inverse MAE weighting: lower error = higher weight
        inverse_maes =
          Map.new(model_stats, fn {model, %{mae: mae}} ->
            {model, 1.0 / max(mae, 0.5)}
          end)

        total = inverse_maes |> Map.values() |> Enum.sum()

        Map.new(inverse_maes, fn {model, inv_mae} ->
          {model, inv_mae / total}
        end)

      _ ->
        # Not enough data — equal weighting
        %{}
    end
  end

  defp extract_temps(snapshots, unit) do
    Enum.map(snapshots, fn snapshot ->
      temp = snapshot.max_temp_c
      if unit == "F", do: round(temp * 9 / 5 + 32), else: round(temp)
    end)
  end

  defp build_weighted_empirical(temps, _snapshots, model_weights) when model_weights == %{} do
    # Equal weighting fallback
    total = length(temps)

    temps
    |> Enum.frequencies()
    |> Map.new(fn {temp, count} -> {temp, count / total} end)
  end

  defp build_weighted_empirical(_temps, snapshots, model_weights) do
    # Weighted: each model's temp gets its accuracy-based weight
    total_weight =
      Enum.reduce(snapshots, 0.0, fn s, acc ->
        acc + Map.get(model_weights, s.model, 1.0 / map_size(model_weights))
      end)

    Enum.reduce(snapshots, %{}, fn snapshot, acc ->
      temp = round(snapshot.max_temp_c)
      weight = Map.get(model_weights, snapshot.model, 1.0 / map_size(model_weights))
      normalized_weight = weight / total_weight
      Map.update(acc, temp, normalized_weight, &(&1 + normalized_weight))
    end)
  end

  defp collapse_tails(prob_map, nil, nil, unit), do: label_outcomes(prob_map, unit)

  defp collapse_tails(prob_map, lower_bound, upper_bound, unit) do
    u = unit_suffix(unit)

    {below, within, above} =
      Enum.reduce(prob_map, {0.0, [], 0.0}, fn {temp, prob}, {below_acc, within_acc, above_acc} ->
        cond do
          lower_bound && temp < lower_bound ->
            {below_acc + prob, within_acc, above_acc}

          upper_bound && temp > upper_bound ->
            {below_acc, within_acc, above_acc + prob}

          true ->
            {below_acc, [{temp, prob} | within_acc], above_acc}
        end
      end)

    result = Map.new(within, fn {temp, prob} -> {"#{temp}#{u}", prob} end)

    result =
      if lower_bound && below > 0,
        do: Map.put(result, "#{lower_bound}#{u} or below", below),
        else: result

    result =
      if upper_bound && above > 0,
        do: Map.put(result, "#{upper_bound}#{u} or higher", above),
        else: result

    result
  end

  defp label_outcomes(prob_map, unit) do
    u = unit_suffix(unit)
    Map.new(prob_map, fn {temp, prob} -> {"#{temp}#{u}", prob} end)
  end

  defp unit_suffix("F"), do: "F"
  defp unit_suffix(_), do: "C"

  defp to_distribution(labeled_probs) do
    # Normalize to ensure sum = 1.0
    total = labeled_probs |> Map.values() |> Enum.sum()

    normalized =
      if total > 0 do
        Map.new(labeled_probs, fn {label, prob} -> {label, prob / total} end)
      else
        labeled_probs
      end

    %Distribution{probabilities: normalized}
  end
end
