defmodule WeatherEdge.Calibration do
  @moduledoc """
  Context for querying forecast accuracy and calibration data.
  """

  import Ecto.Query
  alias WeatherEdge.Repo
  alias WeatherEdge.Calibration.Accuracy

  @doc """
  Lists all accuracy records ordered by target_date desc.
  """
  def list_accuracy(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Accuracy
    |> order_by([a], desc: a.target_date)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns daily P&L data from closed positions for charting.
  Groups by close date, sums realized_pnl.
  """
  def daily_pnl(opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    since = Date.add(Date.utc_today(), -days)

    WeatherEdge.Trading.Position
    |> where([p], p.status != "open" and not is_nil(p.closed_at))
    |> where([p], fragment("?::date", p.closed_at) >= ^since)
    |> group_by([p], fragment("?::date", p.closed_at))
    |> select([p], %{
      date: fragment("?::date", p.closed_at),
      pnl: sum(p.realized_pnl),
      count: count(p.id)
    })
    |> order_by([p], asc: fragment("?::date", p.closed_at))
    |> Repo.all()
  end

  @doc """
  Returns overall stats summary.
  """
  def summary_stats do
    accuracy_records = list_accuracy()
    count = length(accuracy_records)
    hit_count = Enum.count(accuracy_records, & &1.resolution_correct)

    auto_buy_records = Enum.filter(accuracy_records, & &1.auto_buy_pnl)
    auto_buy_pnl = Enum.reduce(auto_buy_records, 0.0, fn r, acc -> acc + (r.auto_buy_pnl || 0.0) end)
    auto_buy_wins = Enum.count(auto_buy_records, fn r -> r.auto_buy_outcome == "win" end)

    # Also count resolved events from positions when no accuracy records yet
    {resolved_count, resolved_wins} =
      if count == 0 do
        resolved_positions =
          WeatherEdge.Trading.Position
          |> where([p], p.status in ["resolved_win", "resolved_loss"])
          |> Repo.all()

        r_count =
          resolved_positions
          |> Enum.map(& &1.market_cluster_id)
          |> Enum.uniq()
          |> length()

        r_wins = Enum.count(resolved_positions, &(&1.status == "resolved_win"))
        {r_count, r_wins}
      else
        {count, hit_count}
      end

    total_resolved = max(count, resolved_count)
    total_hits = max(hit_count, resolved_wins)

    %{
      total_events: total_resolved,
      hit_rate: if(total_resolved > 0, do: total_hits / total_resolved, else: 0.0),
      auto_buy_count: length(auto_buy_records),
      auto_buy_wins: auto_buy_wins,
      auto_buy_total_pnl: auto_buy_pnl
    }
  end
end
