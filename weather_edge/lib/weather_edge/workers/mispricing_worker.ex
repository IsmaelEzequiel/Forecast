defmodule WeatherEdge.Workers.MispricingWorker do
  @moduledoc """
  Generates mispricing signals every 5 minutes by comparing forecast probability
  distributions to current market prices for all active market clusters.
  """

  use Oban.Worker, queue: :signals

  require Logger

  alias WeatherEdge.Markets
  alias WeatherEdge.Forecasts.MetarClient
  alias WeatherEdge.Probability.Engine
  alias WeatherEdge.Signals
  alias WeatherEdge.Signals.{Alerter, Detector}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    clusters = Markets.get_active_clusters()

    Logger.info("MispricingWorker: Scanning #{length(clusters)} active cluster(s)")

    # Pre-fetch observed highs for today's stations to avoid duplicate API calls
    today = Date.utc_today()

    observed_highs =
      clusters
      |> Enum.filter(&(&1.target_date == today))
      |> Enum.map(& &1.station_code)
      |> Enum.uniq()
      |> Enum.into(%{}, fn code ->
        high =
          case MetarClient.get_todays_high(code) do
            {:ok, temp} -> temp
            _ -> nil
          end

        {code, high}
      end)

    Enum.each(clusters, fn cluster ->
      process_cluster(cluster, observed_highs)
    end)

    :ok
  end

  defp process_cluster(cluster, observed_highs) do
    # For today's markets, pass the observed high so the detector can skip resolved outcomes
    detector_opts =
      if cluster.target_date == Date.utc_today() do
        case Map.get(observed_highs, cluster.station_code) do
          nil -> []
          temp -> [observed_high_c: temp]
        end
      else
        []
      end

    case Engine.compute_distribution(cluster.station_code, cluster.target_date) do
      {:ok, distribution} ->
        case Detector.detect_mispricings(cluster, distribution, detector_opts) do
          {:ok, signals, _flags} when signals != [] ->
            {:ok, _records} = Signals.store_signals(cluster.id, cluster.station_code, signals)
            Alerter.broadcast_signals(cluster.station_code, signals, cluster.target_date, cluster.event_slug)

            Logger.info(
              "MispricingWorker: #{length(signals)} signal(s) for #{cluster.station_code} event #{cluster.event_id}"
            )

          {:ok, _signals, _flags} ->
            :ok
        end

      {:error, :no_forecasts} ->
        Logger.debug(
          "MispricingWorker: No forecasts for #{cluster.station_code} #{cluster.target_date}, skipping"
        )

      {:error, reason} ->
        Logger.error(
          "MispricingWorker: Failed for cluster #{cluster.id}: #{inspect(reason)}"
        )
    end
  rescue
    e ->
      Logger.error(
        "MispricingWorker: Error processing cluster #{cluster.id}: #{Exception.message(e)}"
      )
  end
end
