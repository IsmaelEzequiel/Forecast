defmodule WeatherEdge.Markets do
  @moduledoc """
  Context for managing market clusters and event data.
  """

  import Ecto.Query
  alias WeatherEdge.Repo
  alias WeatherEdge.Markets.MarketCluster

  def create_market_cluster(attrs) do
    %MarketCluster{}
    |> MarketCluster.changeset(attrs)
    |> Repo.insert()
  end

  def get_active_clusters do
    MarketCluster
    |> where([mc], mc.resolved == false)
    |> order_by([mc], asc: mc.target_date)
    |> Repo.all()
  end

  def get_clusters_for_station(station_code) do
    MarketCluster
    |> where([mc], mc.station_code == ^station_code)
    |> order_by([mc], asc: mc.target_date)
    |> Repo.all()
  end

  def get_by_event_id(event_id) do
    Repo.get_by(MarketCluster, event_id: event_id)
  end

  def station_codes_with_active_clusters do
    MarketCluster
    |> where([mc], mc.resolved == false)
    |> select([mc], mc.station_code)
    |> distinct(true)
    |> Repo.all()
  end

  def active_clusters_for_station(station_code) do
    MarketCluster
    |> where([mc], mc.station_code == ^station_code and mc.resolved == false)
    |> Repo.all()
  end

  def mark_resolved(market_cluster_id, resolution_temp) do
    case Repo.get(MarketCluster, market_cluster_id) do
      nil ->
        {:error, :not_found}

      cluster ->
        cluster
        |> MarketCluster.changeset(%{resolved: true, resolution_temp: resolution_temp})
        |> Repo.update()
    end
  end
end
