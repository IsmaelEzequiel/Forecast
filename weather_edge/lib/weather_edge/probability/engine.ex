defmodule WeatherEdge.Probability.Engine do
  @moduledoc """
  Probability engine that combines multi-model forecasts into a
  probability distribution across temperature outcomes.
  """

  alias WeatherEdge.Forecasts
  alias WeatherEdge.Probability.{Distribution, Gaussian}

  @doc """
  Computes a probability distribution for temperature outcomes given a station and target date.

  1. Fetches the latest forecast snapshot per model
  2. Rounds each model's max temp to nearest integer
  3. Builds empirical distribution from frequency counts
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

      distribution =
        snapshots
        |> extract_temps(unit)
        |> build_empirical()
        |> Gaussian.apply_kernel(sigma)
        |> collapse_tails(lower_bound, upper_bound, unit)
        |> to_distribution()

      {:ok, distribution}
    end
  end

  defp extract_temps(snapshots, unit) do
    Enum.map(snapshots, fn snapshot ->
      temp = snapshot.max_temp_c
      if unit == "F", do: round(temp * 9 / 5 + 32), else: round(temp)
    end)
  end

  defp build_empirical(temps) do
    total = length(temps)

    temps
    |> Enum.frequencies()
    |> Map.new(fn {temp, count} -> {temp, count / total} end)
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
