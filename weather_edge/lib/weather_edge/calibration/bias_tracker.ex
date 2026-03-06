defmodule WeatherEdge.Calibration.BiasTracker do
  @moduledoc """
  Computes forecast accuracy statistics per station and per model.
  Provides mean error, MAE, and hit rate metrics.
  """

  alias WeatherEdge.Repo
  alias WeatherEdge.Calibration.Accuracy

  import Ecto.Query

  @doc """
  Returns aggregated accuracy statistics for a station across all resolutions.

  Returns a map with:
  - :count - number of resolved events
  - :mean_error - average signed error across all models
  - :mae - mean absolute error across all models
  - :hit_rate - fraction of events where top prediction matched actual temp
  - :model_stats - per-model breakdown from all resolutions
  """
  @spec stats_for_station(String.t()) :: map()
  def stats_for_station(station_code) do
    records =
      Accuracy
      |> where([a], a.station_code == ^station_code)
      |> Repo.all()

    compute_stats(records)
  end

  @doc """
  Returns accuracy statistics for a specific model at a given station.

  Returns a map with:
  - :count - number of resolutions where this model had data
  - :mean_error - average signed error (positive = predicted too high)
  - :mae - mean absolute error
  - :hit_rate - fraction where this model's prediction was closest to actual
  """
  @spec stats_for_model(String.t(), String.t()) :: map()
  def stats_for_model(station_code, model) do
    records =
      Accuracy
      |> where([a], a.station_code == ^station_code)
      |> Repo.all()

    model_entries =
      records
      |> Enum.flat_map(fn record ->
        case Map.get(record.model_errors || %{}, model) do
          nil -> []
          entry -> [entry]
        end
      end)

    case model_entries do
      [] ->
        %{count: 0, mean_error: 0.0, mae: 0.0, hit_rate: 0.0}

      entries ->
        count = length(entries)
        errors = Enum.map(entries, & &1["error"])
        abs_errors = Enum.map(entries, & &1["absolute_error"])

        hit_count =
          Enum.count(records, fn record ->
            case Map.get(record.model_errors || %{}, model) do
              nil ->
                false

              entry ->
                all_abs =
                  record.model_errors
                  |> Map.values()
                  |> Enum.map(& &1["absolute_error"])

                min_abs = Enum.min(all_abs)
                entry["absolute_error"] == min_abs
            end
          end)

        %{
          count: count,
          mean_error: safe_avg(errors),
          mae: safe_avg(abs_errors),
          hit_rate: hit_count / max(length(records), 1)
        }
    end
  end

  defp compute_stats([]), do: %{count: 0, mean_error: 0.0, mae: 0.0, hit_rate: 0.0, model_stats: %{}}

  defp compute_stats(records) do
    count = length(records)
    hit_count = Enum.count(records, & &1.resolution_correct)

    all_model_errors =
      records
      |> Enum.flat_map(fn record ->
        (record.model_errors || %{})
        |> Enum.map(fn {model, entry} -> {model, entry} end)
      end)

    all_errors =
      all_model_errors
      |> Enum.map(fn {_model, entry} -> entry["error"] end)
      |> Enum.reject(&is_nil/1)

    all_abs_errors =
      all_model_errors
      |> Enum.map(fn {_model, entry} -> entry["absolute_error"] end)
      |> Enum.reject(&is_nil/1)

    model_stats =
      all_model_errors
      |> Enum.group_by(fn {model, _} -> model end, fn {_, entry} -> entry end)
      |> Map.new(fn {model, entries} ->
        errors = Enum.map(entries, & &1["error"]) |> Enum.reject(&is_nil/1)
        abs_errors = Enum.map(entries, & &1["absolute_error"]) |> Enum.reject(&is_nil/1)

        {model, %{
          count: length(entries),
          mean_error: safe_avg(errors),
          mae: safe_avg(abs_errors)
        }}
      end)

    %{
      count: count,
      mean_error: safe_avg(all_errors),
      mae: safe_avg(all_abs_errors),
      hit_rate: hit_count / count,
      model_stats: model_stats
    }
  end

  defp safe_avg([]), do: 0.0
  defp safe_avg(list), do: Enum.sum(list) / length(list)
end
