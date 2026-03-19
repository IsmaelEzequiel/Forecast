defmodule WeatherEdge.Workers.DataCleanupWorker do
  @moduledoc """
  Runs daily. Deletes old data older than 30 days to keep the DB lean:
  - forecast_snapshots (high volume, ~10 models * stations * dates * every 15min)
  - market_snapshots (price history, every 5min)
  - orders with status filled/cancelled
  - resolved market_clusters + their positions
  - closed dutch_groups + their dutch_orders
  """

  use Oban.Worker, queue: :cleanup

  require Logger

  import Ecto.Query

  alias WeatherEdge.Repo

  @retention_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff_date = Date.utc_today() |> Date.add(-@retention_days)
    cutoff_dt = DateTime.new!(cutoff_date, ~T[00:00:00], "Etc/UTC")

    results = [
      {:forecast_snapshots, clean_forecast_snapshots(cutoff_dt)},
      {:market_snapshots, clean_market_snapshots(cutoff_dt)},
      {:orders, clean_old_orders(cutoff_dt)},
      {:market_clusters, clean_resolved_clusters(cutoff_date)},
      {:dutch_groups, clean_closed_dutch(cutoff_dt)}
    ]

    Enum.each(results, fn {table, count} ->
      if count > 0, do: Logger.info("DataCleanup: Deleted #{count} rows from #{table}")
    end)

    total = Enum.reduce(results, 0, fn {_, c}, acc -> acc + c end)
    Logger.info("DataCleanup: Total #{total} rows deleted (cutoff: #{cutoff_date})")

    :ok
  end

  defp clean_forecast_snapshots(cutoff_dt) do
    {count, _} =
      from(f in "forecast_snapshots", where: f.fetched_at < ^cutoff_dt)
      |> Repo.delete_all()

    count
  end

  defp clean_market_snapshots(cutoff_dt) do
    {count, _} =
      from(s in "market_snapshots", where: s.snapshot_at < ^cutoff_dt)
      |> Repo.delete_all()

    count
  end

  defp clean_old_orders(cutoff_dt) do
    {count, _} =
      from(o in "orders",
        where: o.placed_at < ^cutoff_dt,
        where: o.status in ["filled", "cancelled", "expired"]
      )
      |> Repo.delete_all()

    count
  end

  defp clean_resolved_clusters(cutoff_date) do
    # Delete resolved clusters where target_date is old
    # Positions referencing them will be kept (they have their own P&L data)
    {count, _} =
      from(mc in "market_clusters",
        where: mc.resolved == true,
        where: mc.target_date < ^cutoff_date
      )
      |> Repo.delete_all()

    count
  end

  defp clean_closed_dutch(cutoff_dt) do
    # dutch_orders cascade-delete via ON DELETE CASCADE
    {count, _} =
      from(dg in "dutch_groups",
        where: dg.status in ["won", "lost", "sold"],
        where: not is_nil(dg.closed_at),
        where: dg.closed_at < ^cutoff_dt
      )
      |> Repo.delete_all()

    count
  end
end
