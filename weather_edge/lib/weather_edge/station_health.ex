defmodule WeatherEdge.StationHealth do
  @moduledoc """
  Checks METAR data freshness for a station.
  Caches results in persistent_term to avoid hitting the API on every render.
  """

  alias WeatherEdge.Forecasts.MetarClient

  @fresh_threshold_min 120
  @stale_threshold_min 360

  @doc """
  Returns :fresh, :stale, :offline, or :unknown based on last METAR observation age.
  Uses cached data, refreshed by the ForecastFetcherWorker.
  """
  @spec check(String.t()) :: :fresh | :stale | :offline | :unknown
  def check(station_code) do
    case :persistent_term.get({:station_health, station_code}, nil) do
      nil -> :unknown
      %{status: status} -> status
    end
  end

  @doc """
  Refreshes health status for a station by fetching current METAR data.
  Called by workers periodically.
  """
  @spec refresh(String.t()) :: :ok
  def refresh(station_code) do
    status =
      case MetarClient.get_current_conditions(station_code) do
        {:ok, %{observed_at: observed_at}} when is_binary(observed_at) ->
          age_status(observed_at)

        {:ok, _} ->
          :fresh

        {:error, _} ->
          :offline
      end

    :persistent_term.put({:station_health, station_code}, %{
      status: status,
      checked_at: DateTime.utc_now()
    })

    :ok
  end

  defp age_status(observed_at_str) do
    case DateTime.from_iso8601(observed_at_str) do
      {:ok, dt, _} ->
        age_minutes = DateTime.diff(DateTime.utc_now(), dt, :minute)

        cond do
          age_minutes <= @fresh_threshold_min -> :fresh
          age_minutes <= @stale_threshold_min -> :stale
          true -> :offline
        end

      _ ->
        :fresh
    end
  end
end
