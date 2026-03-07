defmodule WeatherEdge.Workers.ForecastRefreshWorker do
  @moduledoc """
  Refreshes multi-model forecasts every 15 minutes for all stations
  with active (unresolved) market clusters.
  """

  use Oban.Worker, queue: :forecasts

  require Logger

  alias WeatherEdge.Forecasts
  alias WeatherEdge.Forecasts.OpenMeteoClient
  alias WeatherEdge.Forecasts.WundergroundClient
  alias WeatherEdge.Markets
  alias WeatherEdge.Stations
  alias WeatherEdge.PubSubHelper

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"station_code" => code}}) do
    case Stations.get_by_code(code) do
      {:ok, station} ->
        refresh_station(station)
        WeatherEdge.StationHealth.refresh(station.code)
        Logger.info("ForecastRefresh: Manual refresh for #{code}")

      {:error, :not_found} ->
        Logger.warning("ForecastRefresh: Station #{code} not found")
    end

    :ok
  end

  def perform(%Oban.Job{}) do
    WeatherEdge.JobTracker.start(:forecast_refresh)
    station_codes = Markets.station_codes_with_active_clusters()

    Logger.info("ForecastRefresh: Refreshing forecasts for #{length(station_codes)} station(s)")

    Enum.each(station_codes, fn code ->
      case Stations.get_by_code(code) do
        {:ok, station} ->
          refresh_station(station)
          WeatherEdge.StationHealth.refresh(station.code)

        {:error, :not_found} ->
          Logger.warning("ForecastRefresh: Station #{code} not found")
      end
    end)

    WeatherEdge.JobTracker.finish(:forecast_refresh)
    :ok
  end

  defp refresh_station(station) do
    clusters = Markets.active_clusters_for_station(station.code)
    target_dates = clusters |> Enum.map(& &1.target_date) |> Enum.uniq()

    case OpenMeteoClient.fetch_all_models(station.latitude, station.longitude) do
      {:ok, api_response} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Enum.each(target_dates, fn target_date ->
          daily_maxes = OpenMeteoClient.extract_daily_max(api_response, target_date)

          Enum.each(daily_maxes, fn {model, max_temp} ->
            Forecasts.store_snapshot(%{
              station_code: station.code,
              target_date: target_date,
              model: model,
              max_temp_c: max_temp,
              fetched_at: now
            })
          end)

          # Weather Underground forecast
          fetch_wu_forecast(station, target_date, now)
        end)

        PubSubHelper.broadcast(
          PubSubHelper.station_forecast_update(station.code),
          {:forecast_updated, station.code, length(target_dates)}
        )

        Logger.info(
          "ForecastRefresh: Updated #{station.code} for #{length(target_dates)} target date(s)"
        )

      {:error, reason} ->
        Logger.error("ForecastRefresh: Failed for #{station.code}: #{inspect(reason)}")
    end
  end

  defp fetch_wu_forecast(station, target_date, now) do
    wu_opts = [
      latitude: station.latitude,
      longitude: station.longitude,
      wunderground_url: station.wunderground_url
    ]

    case WundergroundClient.get_forecast_max_temp(station.code, target_date, wu_opts) do
      {:ok, max_temp_c} ->
        Forecasts.store_snapshot(%{
          station_code: station.code,
          target_date: target_date,
          model: "wunderground",
          max_temp_c: max_temp_c,
          fetched_at: now
        })

      {:error, reason} ->
        Logger.debug("ForecastRefresh: WU forecast failed for #{station.code}: #{inspect(reason)}")
    end
  end
end
