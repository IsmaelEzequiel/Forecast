defmodule WeatherEdge.Workers.DutchMonitorWorker do
  @moduledoc """
  Runs every 5 minutes. Updates current prices and sell/hold recommendations
  for all open dutch positions.
  """

  use Oban.Worker, queue: :signals

  require Logger

  alias WeatherEdge.Trading.{DutchGroups, DutchAdvisor, DutchEngine}
  alias WeatherEdge.Markets
  alias WeatherEdge.Probability.Engine
  alias WeatherEdge.Stations
  alias WeatherEdge.PubSubHelper

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    WeatherEdge.JobTracker.start(:dutch_monitor)
    groups = DutchGroups.list_open_with_orders()

    Enum.each(groups, fn group ->
      monitor_group(group)
    end)

    WeatherEdge.JobTracker.finish(:dutch_monitor)
    :ok
  end

  defp monitor_group(group) do
    cluster = Markets.get_cluster(group.market_cluster_id)
    if is_nil(cluster), do: throw(:skip)

    current_prices = build_price_map(cluster.outcomes)

    # Update each order's current price and value
    updated_orders =
      Enum.map(group.dutch_orders, fn order ->
        price = Map.get(current_prices, order.outcome_label, order.buy_price)
        value = order.tokens * price

        DutchGroups.update_order(order, %{current_price: price, current_value: value})

        %{order | current_price: price, current_value: value}
      end)

    # Compute total current value
    current_value = DutchEngine.compute_current_value(updated_orders, current_prices)

    # Get latest forecast for recommendation
    distribution = get_distribution(group)

    # Generate recommendation
    recommendation = DutchAdvisor.recommend(group, updated_orders, current_prices, distribution)

    DutchGroups.update_group(group, %{
      current_value: current_value,
      sell_recommendation: to_string(recommendation.action),
      sell_reason: recommendation.reason
    })

    PubSubHelper.broadcast(
      "dutch:price_update",
      {:dutch_price_update, group.id, updated_orders, recommendation}
    )
  catch
    :skip -> :ok
  end

  defp get_distribution(group) do
    case Stations.get_by_code(group.station_code) do
      {:ok, station} ->
        temp_unit = station.temp_unit || "C"

        case Engine.compute_distribution(group.station_code, group.target_date, temp_unit: temp_unit) do
          {:ok, dist} -> dist
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp build_price_map(outcomes) when is_list(outcomes) do
    Map.new(outcomes, fn o ->
      label = o["outcome_label"] || o["label"] || ""
      price = o["yes_price"] || o["price"] || 0
      {label, price}
    end)
  end

  defp build_price_map(_), do: %{}
end
