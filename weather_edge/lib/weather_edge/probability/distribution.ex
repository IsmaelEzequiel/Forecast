defmodule WeatherEdge.Probability.Distribution do
  @moduledoc """
  Struct representing a probability distribution across temperature outcomes.
  """

  @type t :: %__MODULE__{
          probabilities: %{String.t() => float()}
        }

  defstruct probabilities: %{}

  @doc """
  Returns the outcome with the highest probability.
  """
  @spec top_outcome(t()) :: {String.t(), float()} | nil
  def top_outcome(%__MODULE__{probabilities: probs}) when map_size(probs) == 0, do: nil

  def top_outcome(%__MODULE__{probabilities: probs}) do
    Enum.max_by(probs, fn {_outcome, prob} -> prob end)
  end

  @doc """
  Returns the top N outcomes sorted by probability descending.
  """
  @spec top_n(t(), pos_integer()) :: [{String.t(), float()}]
  def top_n(%__MODULE__{probabilities: probs}, n) do
    probs
    |> Enum.sort_by(fn {_outcome, prob} -> prob end, :desc)
    |> Enum.take(n)
  end

  @doc """
  Returns the probability for a specific outcome label.
  """
  @spec probability_for(t(), String.t()) :: float()
  def probability_for(%__MODULE__{probabilities: probs}, outcome) do
    Map.get(probs, outcome, 0.0)
  end
end
