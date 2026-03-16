defmodule WeatherEdge.Trading.DutchGroups do
  @moduledoc """
  Context for dutch group and order CRUD operations.
  """

  import Ecto.Query

  alias WeatherEdge.Repo
  alias WeatherEdge.Trading.{DutchGroup, DutchOrder}

  def create_group(attrs) do
    %DutchGroup{}
    |> DutchGroup.changeset(attrs)
    |> Repo.insert()
  end

  def create_order(attrs) do
    %DutchOrder{}
    |> DutchOrder.changeset(attrs)
    |> Repo.insert()
  end

  def list_open_with_orders do
    DutchGroup
    |> where([g], g.status == "open")
    |> order_by([g], asc: g.target_date)
    |> preload(:dutch_orders)
    |> Repo.all()
  end

  def list_closed(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    DutchGroup
    |> where([g], g.status in ["won", "lost", "sold"])
    |> order_by([g], desc: g.closed_at)
    |> limit(^limit)
    |> preload(:dutch_orders)
    |> Repo.all()
  end

  def get_group_with_orders(id) do
    DutchGroup
    |> preload(:dutch_orders)
    |> Repo.get(id)
  end

  def update_group(%DutchGroup{} = group, attrs) do
    group
    |> DutchGroup.changeset(attrs)
    |> Repo.update()
  end

  def update_order(%DutchOrder{} = order, attrs) do
    order
    |> DutchOrder.changeset(attrs)
    |> Repo.update()
  end

  def exists_for_cluster?(station_code, cluster_id) do
    DutchGroup
    |> where([g], g.station_code == ^station_code and g.market_cluster_id == ^cluster_id)
    |> Repo.exists?()
  end

  def compute_performance_stats do
    closed =
      DutchGroup
      |> where([g], g.status in ["won", "lost", "sold"])
      |> Repo.all()

    total = length(closed)
    wins = Enum.count(closed, fn g -> g.status in ["won", "sold"] and (g.actual_pnl || 0) > 0 end)
    total_pnl = closed |> Enum.map(fn g -> g.actual_pnl || 0.0 end) |> Enum.sum()

    avg_profit =
      if total > 0, do: total_pnl / total, else: 0.0

    %{
      total_trades: total,
      wins: wins,
      win_rate: if(total > 0, do: wins / total, else: 0.0),
      total_pnl: total_pnl,
      avg_profit: avg_profit
    }
  end
end
