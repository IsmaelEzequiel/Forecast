defmodule WeatherEdge.Probability.Gaussian do
  @moduledoc """
  Gaussian kernel smoothing for temperature probability distributions.
  Spreads probability mass across adjacent temperature outcomes.
  """

  @doc """
  Returns the appropriate sigma based on days out from target date.

  - <= 1 day: 0.8 (tighter distribution, more confident)
  - 2 days: 1.2
  - 3+ days: 1.8 (wider distribution, less confident)
  """
  @spec sigma(non_neg_integer()) :: float()
  def sigma(days_out) when days_out <= 1, do: 0.8
  def sigma(2), do: 1.2
  def sigma(days_out) when days_out >= 3, do: 1.8

  @doc """
  Applies Gaussian kernel smoothing to a raw probability distribution.

  Takes a map of `%{temperature => probability}` and a sigma value,
  returns a smoothed distribution where probability mass is spread
  to neighboring temperatures using a Gaussian kernel.

  The output distribution is normalized to sum to 1.0.
  """
  @spec apply_kernel(map(), number()) :: map()
  def apply_kernel(prob_map, sigma) when is_map(prob_map) and sigma > 0 do
    source_temps = Map.keys(prob_map)

    # Expand target range beyond model predictions to capture tail probability.
    # Without this, temperatures outside the model range get 0% probability,
    # causing false "BUY NO" signals on adjacent outcomes.
    spread = max(round(sigma * 3), 3)
    min_temp = Enum.min(source_temps) - spread
    max_temp = Enum.max(source_temps) + spread
    target_temps = Enum.to_list(min_temp..max_temp)

    target_temps
    |> Enum.map(fn target_temp ->
      smoothed_prob =
        source_temps
        |> Enum.reduce(0.0, fn source_temp, acc ->
          weight = gaussian_weight(source_temp, target_temp, sigma)
          acc + weight * Map.get(prob_map, source_temp, 0.0)
        end)

      {target_temp, smoothed_prob}
    end)
    |> Enum.filter(fn {_temp, prob} -> prob > 1.0e-6 end)
    |> normalize()
  end

  defp gaussian_weight(x, mu, sigma) do
    :math.exp(-:math.pow(x - mu, 2) / (2 * :math.pow(sigma, 2)))
  end

  defp normalize(temp_prob_pairs) do
    total = Enum.reduce(temp_prob_pairs, 0.0, fn {_temp, prob}, acc -> acc + prob end)

    if total == 0.0 do
      Map.new(temp_prob_pairs)
    else
      temp_prob_pairs
      |> Enum.map(fn {temp, prob} -> {temp, prob / total} end)
      |> Map.new()
    end
  end
end
