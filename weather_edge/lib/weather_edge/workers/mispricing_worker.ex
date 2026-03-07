defmodule WeatherEdge.Workers.MispricingWorker do
  @moduledoc """
  Generates mispricing signals by comparing forecast probability distributions
  to current market prices for all active market clusters.

  Uses timezone-aware scanning:
  - Post-peak cities (observed high is final) get `confirmed` confidence
  - Near-peak cities get `high` confidence
  - Pre-peak cities get `forecast` confidence
  """

  use Oban.Worker, queue: :signals

  require Logger

  alias WeatherEdge.Markets
  alias WeatherEdge.Forecasts.MetarClient
  alias WeatherEdge.Probability.Engine
  alias WeatherEdge.Signals
  alias WeatherEdge.Signals.{Alerter, Detector}
  alias WeatherEdge.Stations
  alias WeatherEdge.Timezone.PeakCalculator

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    WeatherEdge.JobTracker.start(:mispricing)
    clusters = Markets.get_active_clusters()

    Logger.info("MispricingWorker: Scanning #{length(clusters)} active cluster(s)")

    now = DateTime.utc_now()
    today = Date.utc_today()

    # Load stations for longitude data
    stations_map =
      Stations.list_stations()
      |> Enum.into(%{}, fn s -> {s.code, s} end)

    # Pre-fetch observed highs for today's stations
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

    # Group clusters by station to calculate peak status once per station
    clusters
    |> Enum.group_by(& &1.station_code)
    |> Enum.each(fn {station_code, station_clusters} ->
      station = Map.get(stations_map, station_code)

      {peak_status, _hours} =
        if station do
          PeakCalculator.peak_status(station.longitude, now)
        else
          {:pre_peak, 6}
        end

      confidence = PeakCalculator.confidence(peak_status) |> Atom.to_string()

      # Determine if we should scan this station now based on adaptive intervals
      should_scan = should_scan_now?(peak_status, now)

      if should_scan do
        Enum.each(station_clusters, fn cluster ->
          process_cluster(cluster, observed_highs, confidence, peak_status)
        end)
      else
        Logger.debug(
          "MispricingWorker: Skipping #{station_code} (#{peak_status}, next scan later)"
        )
      end
    end)

    WeatherEdge.JobTracker.finish(:mispricing)
    :ok
  end

  defp process_cluster(cluster, observed_highs, confidence, peak_status) do
    # For today's markets, pass the observed high so the detector can skip resolved outcomes.
    # Only pass observed_high_c when post-peak or night — the day's high is final.
    # For near-peak, pass it with a flag so detector only uses it for definitive overrides
    # (e.g., observed > outcome → resolved NO). For pre-peak, DON'T pass it at all —
    # morning temps are just current readings, not daily highs.
    detector_opts =
      if cluster.target_date == Date.utc_today() do
        base = [confidence: confidence, peak_status: peak_status]

        case {peak_status, Map.get(observed_highs, cluster.station_code)} do
          {status, temp} when status in [:post_peak, :night] and not is_nil(temp) ->
            [{:observed_high_c, temp} | base]

          {_, _} ->
            # Pre-peak or near-peak: don't pass observed temp to avoid false overrides
            base
        end
      else
        [confidence: confidence]
      end

    # Build distribution with correct temp unit and outcome bounds
    temp_unit =
      case Stations.get_by_code(cluster.station_code) do
        {:ok, station} -> station.temp_unit || "C"
        _ -> "C"
      end
    {lower, upper} = extract_outcome_bounds(cluster.outcomes, temp_unit)

    dist_opts =
      [temp_unit: temp_unit]
      |> then(fn opts -> if lower, do: [{:lower_bound, lower} | opts], else: opts end)
      |> then(fn opts -> if upper, do: [{:upper_bound, upper} | opts], else: opts end)

    case Engine.compute_distribution(cluster.station_code, cluster.target_date, dist_opts) do
      {:ok, distribution} ->
        case Detector.detect_mispricings(cluster, distribution, detector_opts) do
          {:ok, signals, _flags} when signals != [] ->
            {:ok, _records} = Signals.store_signals(cluster.id, cluster.station_code, signals)
            Alerter.broadcast_signals(cluster.station_code, signals, cluster.target_date, cluster.event_slug)

            Logger.info(
              "MispricingWorker: #{length(signals)} signal(s) for #{cluster.station_code} " <>
                "[#{confidence}] event #{cluster.event_id}"
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

  # Extract lower/upper bounds from market outcomes.
  # Polymarket outcomes like "33°F or below" → lower=33, "48°F or higher" → upper=48
  defp extract_outcome_bounds(outcomes, _temp_unit) when is_list(outcomes) do
    labels =
      Enum.map(outcomes, fn o ->
        o["outcome_label"] || o["label"] || ""
      end)

    lower =
      labels
      |> Enum.find_value(fn label ->
        case Regex.run(~r/(-?\d+)\s*°?\s*[CF]\s+or below/i, label) do
          [_, temp] -> String.to_integer(temp)
          _ -> nil
        end
      end)

    upper =
      labels
      |> Enum.find_value(fn label ->
        case Regex.run(~r/(-?\d+)\s*°?\s*[CF]\s+or higher/i, label) do
          [_, temp] -> String.to_integer(temp)
          _ -> nil
        end
      end)

    {lower, upper}
  end

  defp extract_outcome_bounds(_, _), do: {nil, nil}

  # Adaptive scanning: post-peak scans every run (every 5 min from cron),
  # near-peak every run, pre-peak every other run, night every third run.
  # Uses the minute of the hour to determine if this run should scan.
  defp should_scan_now?(peak_status, now) do
    minute = now.minute

    case peak_status do
      :post_peak -> true
      :near_peak -> true
      :pre_peak -> rem(minute, 10) < 5
      :night -> rem(minute, 15) < 5
    end
  end
end
