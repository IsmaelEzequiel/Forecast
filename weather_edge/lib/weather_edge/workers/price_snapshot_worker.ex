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

  @doc "Snapshot a single cluster by ID. Returns :ok or {:error, reason}."
  def snapshot_cluster_by_id(cluster_id) do
    case Repo.get(MarketCluster, cluster_id) do
      nil -> {:error, :not_found}
      cluster ->
        snapshot_cluster(cluster)
        :ok
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    WeatherEdge.JobTracker.start(:price_snapshot)
    clusters = tracked_clusters()

    Logger.info("PriceSnapshotWorker: Snapshotting #{length(clusters)} cluster(s)")

    Enum.each(clusters, fn cluster ->
      snapshot_cluster(cluster)
    end)

    WeatherEdge.JobTracker.finish(:price_snapshot)
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

    # Snapshot each outcome and collect updated prices
    updated_outcomes =
      Enum.map(outcomes, fn outcome ->
        {yes_price, no_price} = snapshot_outcome(cluster, outcome, now)
        outcome
        |> Map.put("yes_price", yes_price)
        |> Map.put("no_price", no_price)
      end)

    # Update cluster with fresh prices so the detector uses current data
    cluster
    |> Ecto.Changeset.change(%{outcomes: updated_outcomes})
    |> Repo.update()

    # Detect if market is resolved (any outcome at 100% or all at 0)
    maybe_auto_resolve(cluster, updated_outcomes)
  rescue
    e ->
      Logger.error(
        "PriceSnapshotWorker: Error snapshotting cluster #{cluster.id}: #{Exception.message(e)}"
      )
  end

  # Returns {yes_price, no_price} for the outcome (keeping old values on failure)
  defp snapshot_outcome(cluster, outcome, now) do
    label = outcome["outcome_label"]
    token_ids = outcome["clob_token_ids"] |> List.wrap() |> List.first() |> strip_token_quotes()
    old_yes = outcome["yes_price"]
    old_no = outcome["no_price"]

    if is_nil(token_ids) do
      Logger.warning("PriceSnapshotWorker: No token ID for outcome #{label} in cluster #{cluster.id}")
      {old_yes, old_no}
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

      {yes_price || old_yes, no_price || old_no}
    end
  rescue
    e ->
      Logger.error(
        "PriceSnapshotWorker: Error fetching prices for outcome #{outcome["outcome_label"]}: #{Exception.message(e)}"
      )
      {outcome["yes_price"], outcome["no_price"]}
  end

  # If any outcome has YES price >= 0.99 (or all are nil/0), Polymarket has resolved this market.
  # Mark it resolved so the mispricing worker stops generating signals for it.
  defp maybe_auto_resolve(cluster, outcomes) do
    has_winner =
      Enum.any?(outcomes, fn o ->
        yes = o["yes_price"]
        is_number(yes) and yes >= 0.99
      end)

    all_dead =
      Enum.all?(outcomes, fn o ->
        yes = o["yes_price"]
        is_nil(yes) or yes == 0.0
      end)

    if has_winner or all_dead do
      unless cluster.resolved do
        Logger.info(
          "PriceSnapshotWorker: Auto-resolving cluster #{cluster.id} (#{cluster.station_code}) — market closed on Polymarket"
        )

        cluster
        |> Ecto.Changeset.change(%{resolved: true})
        |> Repo.update()
      end
    end
  end

  defp clob_client, do: Application.get_env(:weather_edge, :clob_client, WeatherEdge.Trading.ClobClient)

  defp strip_token_quotes(nil), do: nil
  defp strip_token_quotes(s) when is_binary(s), do: String.replace(s, "\"", "")

  defp fetch_price(token_id, side) do
    case clob_client().get_price(token_id, side) do
      {:ok, price} -> price
      {:error, _reason} -> nil
    end
  end
end
