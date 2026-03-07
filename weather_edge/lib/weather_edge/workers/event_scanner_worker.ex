defmodule WeatherEdge.Workers.EventScannerWorker do
  @moduledoc """
  Scans Polymarket for new temperature events via the Gamma API.
  Runs on cron schedule around 6:00 AM ET when new events typically appear.
  """

  use Oban.Worker, queue: :scanner

  require Logger

  alias WeatherEdge.Markets
  alias WeatherEdge.Markets.{GammaClient, EventParser}
  alias WeatherEdge.Stations
  alias WeatherEdge.PubSubHelper

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"station_code" => code}}) do
    case Stations.get_by_code(code) do
      {:ok, station} -> scan_station(station)
      {:error, _} -> Logger.warning("EventScanner: Station #{code} not found")
    end

    :ok
  end

  def perform(%Oban.Job{}) do
    WeatherEdge.JobTracker.start(:event_scanner)

    stations = Stations.list_stations()

    stations
    |> Enum.filter(& &1.monitoring_enabled)
    |> Enum.each(&scan_station/1)

    WeatherEdge.JobTracker.finish(:event_scanner)
    :ok
  end

  defp scan_station(station) do
    case fetch_events_for_station(station) do
      {:ok, events} ->
        events
        |> Enum.each(fn event -> process_event(station, event) end)

      {:error, reason} ->
        Logger.error(
          "EventScanner: Failed to fetch events for #{station.code}: #{inspect(reason)}"
        )
    end
  end

  defp fetch_events_for_station(station) do
    case station.tag_slug do
      nil ->
        GammaClient.get_events(active: true, closed: false, limit: 50)

      tag_slug ->
        GammaClient.get_events(active: true, closed: false, limit: 50, tag_slug: tag_slug)
    end
  end

  defp process_event(station, raw_event) do
    event_id = to_string(Map.get(raw_event, "id", ""))

    if event_id != "" and matches_station?(station, raw_event) and
         Markets.get_by_event_id(event_id) == nil do
      case EventParser.parse_event(raw_event) do
        {:ok, attrs} ->
          attrs = Map.put(attrs, :station_code, station.code)

          case Markets.create_market_cluster(attrs) do
            {:ok, cluster} ->
              Logger.info(
                "EventScanner: New event detected for #{station.code}: #{cluster.title}"
              )

              PubSubHelper.broadcast(
                PubSubHelper.station_new_event(station.code),
                {:new_event, station.code, cluster}
              )

              maybe_enqueue_auto_buyer(station, cluster)

            {:error, reason} ->
              Logger.error(
                "EventScanner: Failed to create cluster for event #{event_id}: #{inspect(reason)}"
              )
          end

        {:error, reason} ->
          Logger.warning(
            "EventScanner: Failed to parse event #{event_id}: #{inspect(reason)}"
          )
      end
    end
  end

  defp matches_station?(station, event) do
    slug = Map.get(event, "slug", "") |> String.downcase()

    slug_match =
      case station.slug_pattern do
        nil ->
          false

        pattern ->
          slug_regex =
            pattern
            |> Regex.escape()
            |> String.replace("\\*", ".*")

          Regex.match?(~r/#{slug_regex}/i, slug)
      end

    slug_match
  end

  defp maybe_enqueue_auto_buyer(station, cluster) do
    if station.auto_buy_enabled do
      %{station_code: station.code, event_id: cluster.event_id}
      |> WeatherEdge.Workers.AutoBuyerWorker.new(queue: :trading)
      |> Oban.insert()
    end
  end
end
