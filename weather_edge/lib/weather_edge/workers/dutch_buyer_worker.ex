defmodule WeatherEdge.Workers.DutchBuyerWorker do
  @moduledoc """
  Triggered by EventScannerWorker when a new temperature event is detected.
  Executes dutching strategy: buys YES on multiple outcomes to guarantee profit
  when sum of YES prices < $1.00.
  """

  use Oban.Worker, queue: :trading, max_attempts: 2, priority: 0

  require Logger

  alias WeatherEdge.Stations
  alias WeatherEdge.Markets
  alias WeatherEdge.Probability.Engine
  alias WeatherEdge.Trading.{DutchEngine, DutchGroups, OrderManager}
  alias WeatherEdge.PubSubHelper

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"station_code" => code, "cluster_id" => cluster_id}}) do
    WeatherEdge.JobTracker.start(:dutch_buyer)

    with {:ok, station} <- Stations.get_by_code(code),
         true <- station.strategy == "dutch",
         false <- DutchGroups.exists_for_cluster?(code, cluster_id),
         cluster when not is_nil(cluster) <- Markets.get_cluster(cluster_id) do
      execute_dutch(station, cluster)
    else
      {:error, :not_found} ->
        Logger.warning("DutchBuyer: Station #{code} not found")

      true ->
        Logger.debug("DutchBuyer: Group already exists for #{code}/#{cluster_id}")

      false ->
        Logger.debug("DutchBuyer: Station #{code} not using dutch strategy")

      nil ->
        Logger.warning("DutchBuyer: Cluster #{cluster_id} not found")

      _ ->
        :ok
    end

    WeatherEdge.JobTracker.finish(:dutch_buyer)
    :ok
  end

  defp execute_dutch(station, cluster) do
    temp_unit = station.temp_unit || "C"

    # SAFETY: Check total sum of ALL YES prices first
    all_prices_sum =
      (cluster.outcomes || [])
      |> Enum.reduce(0.0, fn o, acc -> acc + (o["yes_price"] || o["price"] || 0) end)

    if all_prices_sum >= 0.95 do
      Logger.warning("DutchBuyer: #{station.code} BLOCKED — total sum YES $#{Float.round(all_prices_sum, 2)} >= $0.95. No dutching opportunity.")
      return_early()
    end

    case Engine.compute_distribution(station.code, cluster.target_date, temp_unit: temp_unit) do
      {:ok, dist} ->
        live_prices = build_price_map(cluster.outcomes)

        config = %{
          dutch_max_sum: station.dutch_max_sum || 0.85,
          dutch_min_coverage: station.dutch_min_coverage || 0.70,
          dutch_max_outcomes: station.dutch_max_outcomes || 5
        }

        selection = DutchEngine.select_outcomes(cluster.outcomes, dist, live_prices, config)

        min_profit = station.dutch_min_profit_pct || 0.05

        cond do
          not selection.is_profitable ->
            Logger.info("DutchBuyer: #{station.code} not profitable (sum=#{Float.round(selection.sum_prices, 3)})")

          selection.profit_pct < min_profit ->
            Logger.info("DutchBuyer: #{station.code} profit #{Float.round(selection.profit_pct * 100, 1)}% below min #{Float.round(min_profit * 100, 1)}%")

          length(selection.outcomes) < 2 ->
            Logger.info("DutchBuyer: #{station.code} only #{length(selection.outcomes)} outcomes selected, need >= 2")

          true ->
            budget = station.buy_amount_usdc || 50.0
            allocation = DutchEngine.compute_allocation(selection, budget)

            if allocation do
              place_dutch_orders(station, cluster, selection, allocation)
            end
        end

      {:error, reason} ->
        Logger.error("DutchBuyer: Distribution failed for #{station.code}: #{inspect(reason)}")
    end
  end

  defp place_dutch_orders(station, cluster, selection, allocation) do
    balance = :persistent_term.get(:sidecar_balance, 0.0) || 0.0
    min_reserve = Application.get_env(:weather_edge, :trading)[:min_reserve_usdc] || 2.0

    if balance < allocation.total_invested + min_reserve do
      Logger.warning("DutchBuyer: Insufficient balance for #{station.code} (need $#{Float.round(allocation.total_invested + min_reserve, 2)}, have $#{Float.round(balance, 2)})")
      return_early()
    end

    Logger.info("DutchBuyer: Executing dutch for #{station.code} — #{length(allocation.orders)} outcomes, $#{Float.round(allocation.total_invested, 2)} budget, #{Float.round(allocation.profit_pct * 100, 1)}% expected profit")

    results =
      allocation.orders
      |> Enum.with_index(1)
      |> Enum.map(fn {order, n} ->
        outcome = %{
          "token_id" => order.token_id,
          "outcome_label" => order.outcome_label,
          "price" => order.buy_price,
          "market_cluster_id" => cluster.id,
          "event_id" => cluster.event_slug,
          "auto_order" => true
        }

        Logger.info("DutchBuyer: Order #{n}/#{length(allocation.orders)} — #{order.outcome_label} @ $#{Float.round(order.buy_price, 3)}")

        result = OrderManager.place_buy_order(station.code, outcome, order.invested)

        if n < length(allocation.orders), do: Process.sleep(2_000)

        {order, result}
      end)

    successful = Enum.filter(results, fn {_, result} -> match?({:ok, _}, result) end)
    failed = length(results) - length(successful)

    if length(successful) > 0 do
      {:ok, group} =
        DutchGroups.create_group(%{
          station_code: station.code,
          market_cluster_id: cluster.id,
          target_date: cluster.target_date,
          total_invested: allocation.total_invested,
          guaranteed_payout: allocation.guaranteed_payout,
          guaranteed_profit_pct: allocation.profit_pct,
          coverage: selection.coverage,
          num_outcomes: length(successful),
          current_value: allocation.total_invested
        })

      Enum.each(successful, fn {order, {:ok, placed_order}} ->
        DutchGroups.create_order(%{
          dutch_group_id: group.id,
          outcome_label: order.outcome_label,
          token_id_yes: order.token_id,
          buy_price: order.buy_price,
          tokens: order.tokens,
          invested: order.invested,
          current_price: order.buy_price,
          current_value: order.invested,
          polymarket_order_id: if(is_map(placed_order), do: Map.get(placed_order, :order_id))
        })
      end)

      Logger.info("DutchBuyer: #{station.code} dutch complete — #{length(successful)} orders, #{failed} failed")

      PubSubHelper.broadcast("dutch:new_position", {:dutch_new_position, DutchGroups.get_group_with_orders(group.id)})
    else
      Logger.error("DutchBuyer: All orders failed for #{station.code}")
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

  defp return_early, do: :ok
end
