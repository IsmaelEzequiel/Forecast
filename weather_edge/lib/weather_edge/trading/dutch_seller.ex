defmodule WeatherEdge.Trading.DutchSeller do
  @moduledoc """
  Executes sell orders for dutch groups.
  """

  require Logger

  alias WeatherEdge.Trading.{DutchGroups, OrderManager}
  alias WeatherEdge.PubSubHelper

  @doc """
  Sell all positions in a dutch group at market price.
  """
  def sell_all(dutch_group_id) do
    case DutchGroups.get_group_with_orders(dutch_group_id) do
      nil ->
        {:error, :not_found}

      group ->
        results =
          Enum.map(group.dutch_orders, fn order ->
            sell_single_order(group.station_code, order)
          end)

        total_received = results |> Enum.map(fn {_, v} -> v end) |> Enum.sum()
        actual_pnl = total_received - group.total_invested

        DutchGroups.update_group(group, %{
          status: "sold",
          actual_pnl: actual_pnl,
          current_value: total_received,
          closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        result = %{
          group_id: group.id,
          total_received: total_received,
          actual_pnl: actual_pnl,
          station_code: group.station_code,
          target_date: group.target_date
        }

        PubSubHelper.broadcast("dutch:sold", {:dutch_sold, group.id, result})

        {:ok, result}
    end
  end

  @doc """
  Sell all with progress callbacks for LiveView updates.
  """
  def sell_all_with_progress(dutch_group_id, progress_fn) do
    case DutchGroups.get_group_with_orders(dutch_group_id) do
      nil ->
        {:error, :not_found}

      group ->
        total = length(group.dutch_orders)

        results =
          group.dutch_orders
          |> Enum.with_index(1)
          |> Enum.map(fn {order, n} ->
            result = sell_single_order(group.station_code, order)
            progress_fn.({:completed, n, total})
            Process.sleep(2_000)
            result
          end)

        total_received = results |> Enum.map(fn {_, v} -> v end) |> Enum.sum()
        actual_pnl = total_received - group.total_invested

        DutchGroups.update_group(group, %{
          status: "sold",
          actual_pnl: actual_pnl,
          current_value: total_received,
          closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        result = %{
          group_id: group.id,
          total_received: total_received,
          actual_pnl: actual_pnl,
          station_code: group.station_code,
          target_date: group.target_date
        }

        PubSubHelper.broadcast("dutch:sold", {:dutch_sold, group.id, result})
        progress_fn.({:done, result})

        {:ok, result}
    end
  end

  defp sell_single_order(station_code, order) do
    # Build sell outcome for OrderManager
    sell_price = order.current_price || order.buy_price
    amount = order.tokens * sell_price

    outcome = %{
      "token_id" => order.token_id_yes,
      "outcome_label" => order.outcome_label,
      "price" => sell_price,
      "market_cluster_id" => nil,
      "event_id" => nil,
      "auto_order" => true
    }

    case OrderManager.place_buy_order(station_code, outcome, amount) do
      {:ok, _order} ->
        received = order.tokens * sell_price
        {:ok, received}

      {:error, reason} ->
        Logger.warning("DutchSeller: Failed to sell #{order.outcome_label}: #{inspect(reason)}")
        # Return estimated value even on failure
        {:error, order.tokens * (order.current_price || order.buy_price)}
    end
  end
end
