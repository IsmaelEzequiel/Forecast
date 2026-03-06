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

  @pubsub WeatherEdge.PubSub

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    stations = Stations.list_stations()

    stations
    |> Enum.filter(& &1.monitoring_enabled)
    |> Enum.each(&scan_station/1)

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
    case station.slug_pattern do
      nil ->
        GammaClient.get_events(active: true, closed: false, limit: 50)

      pattern ->
        slug_base = pattern |> String.replace("*", "") |> String.trim_trailing("-")
        GammaClient.get_events(active: true, closed: false, limit: 50, slug: slug_base)
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

              Phoenix.PubSub.broadcast(
                @pubsub,
                "station:#{station.code}:new_event",
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
    title = Map.get(event, "title", "") |> String.downcase()
    slug = Map.get(event, "slug", "") |> String.downcase()
    city = (station.city || "") |> String.downcase()

    city_match = city != "" and (String.contains?(title, city) or String.contains?(slug, city))

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

    city_match or slug_match
  end

  defp maybe_enqueue_auto_buyer(station, cluster) do
    if station.auto_buy_enabled do
      %{station_code: station.code, event_id: cluster.event_id}
      |> WeatherEdge.Workers.AutoBuyerWorker.new(queue: :trading)
      |> Oban.insert()
    end
  end
end
