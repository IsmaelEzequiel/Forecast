defmodule WeatherEdge.Workers.MispricingWorker do
  @moduledoc """
  Generates mispricing signals every 5 minutes by comparing forecast probability
  distributions to current market prices for all active market clusters.
  """

  use Oban.Worker, queue: :signals

  require Logger

  alias WeatherEdge.Markets
  alias WeatherEdge.Probability.Engine
  alias WeatherEdge.Signals
  alias WeatherEdge.Signals.{Alerter, Detector}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    clusters = Markets.get_active_clusters()

    Logger.info("MispricingWorker: Scanning #{length(clusters)} active cluster(s)")

    Enum.each(clusters, fn cluster ->
      process_cluster(cluster)
    end)

    :ok
  end

  defp process_cluster(cluster) do
    case Engine.compute_distribution(cluster.station_code, cluster.target_date) do
      {:ok, distribution} ->
        case Detector.detect_mispricings(cluster, distribution) do
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
