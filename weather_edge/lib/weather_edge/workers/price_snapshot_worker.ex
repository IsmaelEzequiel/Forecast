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

    updated_outcomes =
      Enum.map(outcomes, fn outcome ->
        label = outcome["outcome_label"] || ""
        token_id = outcome["clob_token_ids"] |> List.wrap() |> List.first() |> strip_token_quotes()
        old_yes = outcome["yes_price"]
        old_no = outcome["no_price"]

        yes_price =
          if token_id do
            case fetch_last_trade_price(token_id) do
              {:ok, price} when price > 0 -> price
              _ -> old_yes
            end
          else
            old_yes
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

    cluster
    |> Ecto.Changeset.change(%{outcomes: updated_outcomes})
    |> Repo.update()

    maybe_auto_resolve(cluster, updated_outcomes)
  rescue
    e ->
      Logger.error("PriceSnapshotWorker: Error snapshotting cluster #{cluster.id}: #{Exception.message(e)}")
  end

  # CLOB /last-trade-price — returns last traded price, defaults to 0.5 if no trades
  defp fetch_last_trade_price(token_id) do
    url = "https://clob.polymarket.com/last-trade-price"

    case Req.get(url, params: [token_id: token_id], receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: %{"price" => price}}} when is_binary(price) ->
        case Float.parse(price) do
          {val, _} -> {:ok, val}
          :error -> {:error, :parse_error}
        end

      {:ok, %Req.Response{status: 200, body: %{"price" => price}}} when is_number(price) ->
        {:ok, price / 1}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
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

  defp strip_token_quotes(nil), do: nil
  defp strip_token_quotes(s) when is_binary(s), do: String.replace(s, "\"", "")
end
