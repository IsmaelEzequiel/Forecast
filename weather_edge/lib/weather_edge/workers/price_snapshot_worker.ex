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

    # Build token list for batch midpoint fetch via sidecar
    midpoint_map = fetch_midpoints(outcomes)

    # Update each outcome with fresh prices
    updated_outcomes =
      Enum.map(outcomes, fn outcome ->
        label = outcome["outcome_label"] || ""
        token_id = outcome["clob_token_ids"] |> List.wrap() |> List.first() |> strip_token_quotes()
        old_yes = outcome["yes_price"]
        old_no = outcome["no_price"]

        yes_price =
          case Map.get(midpoint_map, token_id) do
            mid when is_number(mid) and mid > 0 -> mid
            _ -> fetch_price(token_id, "buy") || old_yes
          end

        no_price = if is_number(yes_price) and yes_price > 0, do: Float.round(1.0 - yes_price, 4), else: old_no

        # Store snapshot
        if token_id do
          attrs = %{
            market_cluster_id: cluster.id,
            snapshot_at: now,
            outcome_label: label,
            yes_price: yes_price,
            no_price: no_price
          }

          case %MarketSnapshot{} |> MarketSnapshot.changeset(attrs) |> Repo.insert() do
            {:ok, _} -> :ok
            {:error, cs} -> Logger.error("PriceSnapshotWorker: Snapshot insert failed for #{label}: #{inspect(cs.errors)}")
          end
        end

        outcome
        |> Map.put("yes_price", yes_price)
        |> Map.put("no_price", no_price)
      end)

    # Update cluster with fresh prices
    cluster
    |> Ecto.Changeset.change(%{outcomes: updated_outcomes})
    |> Repo.update()

    maybe_auto_resolve(cluster, updated_outcomes)
  rescue
    e ->
      Logger.error("PriceSnapshotWorker: Error snapshotting cluster #{cluster.id}: #{Exception.message(e)}")
  end

  # Batch fetch midpoint prices from sidecar (official Polymarket SDK)
  defp fetch_midpoints(outcomes) do
    token_entries =
      outcomes
      |> Enum.map(fn o ->
        token_id = o["clob_token_ids"] |> List.wrap() |> List.first() |> strip_token_quotes()
        label = o["outcome_label"] || ""
        %{token_id: token_id, label: label}
      end)
      |> Enum.filter(fn e -> e.token_id != nil end)

    case WeatherEdge.Trading.SidecarClient.get_midpoints(token_entries) do
      {:ok, prices} when is_list(prices) ->
        Map.new(prices, fn p ->
          {p["token_id"], p["midpoint"] || 0}
        end)

      {:error, reason} ->
        Logger.warning("PriceSnapshotWorker: Sidecar midpoints failed (#{inspect(reason)}), falling back to CLOB")
        %{}
    end
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
