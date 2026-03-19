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

    # Primary: re-fetch prices from Gamma API (same source as Polymarket UI)
    gamma_prices = fetch_gamma_prices(cluster)

    outcomes = cluster.outcomes || []

    updated_outcomes =
      Enum.map(outcomes, fn outcome ->
        label = outcome["outcome_label"] || ""
        question = outcome["question"] || ""
        old_yes = outcome["yes_price"]
        old_no = outcome["no_price"]

        # Match by question text against Gamma response
        {yes_price, no_price} =
          case Map.get(gamma_prices, question) do
            {gyes, gno} when is_number(gyes) and gyes > 0 -> {gyes, gno}
            _ -> {old_yes, old_no}
          end

        # Store snapshot
        token_id = outcome["clob_token_ids"] |> List.wrap() |> List.first() |> strip_token_quotes()

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

  # Fetch fresh prices from Gamma API by event slug (same source as Polymarket UI)
  defp fetch_gamma_prices(cluster) do
    slug = cluster.event_slug

    if slug do
      case WeatherEdge.Markets.GammaClient.get_event_by_slug(slug) do
        {:ok, event} ->
          markets = Map.get(event, "markets", [])

          Map.new(markets, fn m ->
            question = Map.get(m, "question", "")
            outcome_prices = Map.get(m, "outcomePrices", "")

            {yes, no} =
              case Jason.decode(outcome_prices) do
                {:ok, [yes_str, no_str | _]} ->
                  {safe_float(yes_str), safe_float(no_str)}

                {:ok, [yes_str]} ->
                  y = safe_float(yes_str)
                  {y, Float.round(1.0 - y, 4)}

                _ ->
                  {0.0, 0.0}
              end

            {question, {yes, no}}
          end)

        {:error, reason} ->
          Logger.warning("PriceSnapshotWorker: Gamma fetch failed for #{slug}: #{inspect(reason)}")
          %{}
      end
    else
      %{}
    end
  end

  defp safe_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp safe_float(val) when is_number(val), do: val / 1
  defp safe_float(_), do: 0.0

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
