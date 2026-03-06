defmodule WeatherEdge.Workers.PriceSnapshotWorker do
  @moduledoc """
  Captures price snapshots every 5 minutes for all tracked markets
  (active clusters + clusters with open positions) and stores them
  in the market_snapshots hypertable.
  """

  use Oban.Worker, queue: :signals

  require Logger

  import Ecto.Query

  alias WeatherEdge.Markets.{MarketCluster, MarketSnapshot}
  alias WeatherEdge.Repo
  alias WeatherEdge.Trading.Position

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    clusters = tracked_clusters()

    Logger.info("PriceSnapshotWorker: Snapshotting #{length(clusters)} cluster(s)")

    Enum.each(clusters, fn cluster ->
      snapshot_cluster(cluster)
    end)

    :ok
  end

  defp tracked_clusters do
    active_cluster_ids =
      MarketCluster
      |> where([mc], mc.resolved == false)
      |> select([mc], mc.id)
      |> Repo.all()

    position_cluster_ids =
      Position
      |> where([p], p.status == "open")
      |> select([p], p.market_cluster_id)
      |> distinct(true)
      |> Repo.all()

    cluster_ids = Enum.uniq(active_cluster_ids ++ position_cluster_ids)

    MarketCluster
    |> where([mc], mc.id in ^cluster_ids)
    |> Repo.all()
  end

  defp snapshot_cluster(cluster) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    outcomes = cluster.outcomes || []

    Enum.each(outcomes, fn outcome ->
      snapshot_outcome(cluster, outcome, now)
    end)
  rescue
    e ->
      Logger.error(
        "PriceSnapshotWorker: Error snapshotting cluster #{cluster.id}: #{Exception.message(e)}"
      )
  end

  defp snapshot_outcome(cluster, outcome, now) do
    label = outcome["outcome_label"]
    token_ids = outcome["clob_token_ids"] |> List.wrap() |> List.first()

    if is_nil(token_ids) do
      Logger.warning("PriceSnapshotWorker: No token ID for outcome #{label} in cluster #{cluster.id}")
    else
      yes_price = fetch_price(token_ids, "buy")
      no_price = fetch_price(token_ids, "sell")

      attrs = %{
        market_cluster_id: cluster.id,
        snapshot_at: now,
        outcome_label: label,
        yes_price: yes_price,
        no_price: no_price
      }

      case %MarketSnapshot{} |> MarketSnapshot.changeset(attrs) |> Repo.insert() do
        {:ok, _snapshot} ->
          :ok

        {:error, changeset} ->
          Logger.error(
            "PriceSnapshotWorker: Failed to insert snapshot for #{label}: #{inspect(changeset.errors)}"
          )
      end
    end
  rescue
    e ->
      Logger.error(
        "PriceSnapshotWorker: Error fetching prices for outcome #{outcome["outcome_label"]}: #{Exception.message(e)}"
      )
  end

  defp clob_client, do: Application.get_env(:weather_edge, :clob_client, WeatherEdge.Trading.ClobClient)

  defp fetch_price(token_id, side) do
    case clob_client().get_price(token_id, side) do
      {:ok, price} -> price
      {:error, _reason} -> nil
    end
  end
end
