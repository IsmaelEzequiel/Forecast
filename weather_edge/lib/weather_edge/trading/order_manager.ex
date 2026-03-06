defmodule WeatherEdge.Trading.OrderManager do
  @moduledoc """
  Orchestrates order lifecycle with safety checks.
  Validates balance, enforces rate limits, prevents duplicate orders,
  and manages order/position records.
  """

  require Logger

  alias WeatherEdge.Repo
  alias WeatherEdge.Trading.{ClobClient, DataClient, Order, Position}

  import Ecto.Query

  alias WeatherEdge.PubSubHelper

  @doc """
  Places a BUY order with safety guards.

  Parameters:
    - station_code: the station ICAO code
    - outcome: map with "token_id", "outcome_label", "price" keys
    - amount: USDC amount to spend

  Returns `{:ok, order}` or `{:error, reason}`.
  """
  @spec place_buy_order(String.t(), map(), float()) :: {:ok, Order.t()} | {:error, term()}
  def place_buy_order(station_code, outcome, amount)
      when is_binary(station_code) and is_map(outcome) and is_number(amount) do
    token_id = outcome["token_id"]
    price = outcome["price"]
    label = outcome["outcome_label"]
    market_cluster_id = outcome["market_cluster_id"]
    event_id = outcome["event_id"]

    with :ok <- validate_balance(amount),
         :ok <- validate_no_duplicate(station_code, event_id),
         :ok <- validate_rate_limit(station_code) do
      size = amount / price

      case ClobClient.place_order(token_id, "BUY", price, size) do
        {:ok, response} ->
          order_id = response["orderID"] || response["order_id"] || response["id"]

          order_attrs = %{
            station_code: station_code,
            token_id: token_id,
            order_id: order_id,
            side: "BUY",
            price: price,
            size: size,
            usdc_amount: amount,
            status: "pending",
            auto_order: Map.get(outcome, "auto_order", false),
            placed_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }

          position = find_or_create_position(station_code, market_cluster_id, label, token_id, price, amount)
          order_attrs = Map.put(order_attrs, :position_id, position.id)

          {:ok, order} =
            %Order{}
            |> Order.changeset(order_attrs)
            |> Repo.insert()

          record_rate_limit(station_code)

          Logger.info("Order placed: #{order.id} for #{station_code} #{label} at $#{price}")
          broadcast(:order_placed, order)

          schedule_fill_check(order)

          {:ok, order}

        {:error, reason} ->
          handle_order_failure(station_code, token_id, price, size, amount, outcome, reason)
      end
    end
  end

  @doc """
  Marks an order as filled and updates the associated position.
  """
  @spec mark_filled(Order.t()) :: {:ok, Order.t()}
  def mark_filled(%Order{} = order) do
    {:ok, updated_order} =
      order
      |> Order.changeset(%{
        status: "filled",
        filled_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()

    if order.position_id do
      update_position_on_fill(order)
    end

    Logger.info("Order filled: #{order.id}")
    broadcast(:order_filled, updated_order)

    {:ok, updated_order}
  end

  @doc """
  Marks an order as failed with an error message.
  """
  @spec mark_failed(Order.t(), String.t()) :: {:ok, Order.t()}
  def mark_failed(%Order{} = order, error_message) do
    {:ok, updated_order} =
      order
      |> Order.changeset(%{status: "failed", error_message: error_message})
      |> Repo.update()

    Logger.warning("Order failed: #{order.id} - #{error_message}")
    broadcast(:order_failed, updated_order)

    {:ok, updated_order}
  end

  # --- Safety Guards ---

  defp validate_balance(amount) do
    min_reserve = trading_config()[:min_reserve_usdc] || 2.0

    case DataClient.get_balance() do
      {:ok, balance} when balance >= amount + min_reserve ->
        :ok

      {:ok, balance} ->
        Logger.warning("Insufficient balance: #{balance} USDC, need #{amount + min_reserve}")
        {:error, :insufficient_balance}

      {:error, reason} ->
        Logger.warning("Balance check failed: #{inspect(reason)}")
        {:error, {:balance_check_failed, reason}}
    end
  end

  defp validate_no_duplicate(station_code, event_id) when is_binary(event_id) do
    existing =
      from(o in Order,
        join: p in Position,
        on: o.position_id == p.id,
        join: mc in WeatherEdge.Markets.MarketCluster,
        on: p.market_cluster_id == mc.id,
        where: o.station_code == ^station_code,
        where: mc.event_id == ^event_id,
        where: o.status in ["pending", "filled"],
        select: o.id
      )
      |> Repo.exists?()

    if existing do
      {:error, :duplicate_order}
    else
      :ok
    end
  end

  defp validate_no_duplicate(_station_code, _event_id), do: :ok

  defp validate_rate_limit(station_code) do
    key = rate_limit_key(station_code)

    case :persistent_term.get(key, nil) do
      nil ->
        :ok

      last_order_at ->
        elapsed = System.monotonic_time(:second) - last_order_at

        if elapsed >= 10 do
          :ok
        else
          Logger.warning("Rate limited: #{station_code}, last order #{elapsed}s ago")
          {:error, :rate_limited}
        end
    end
  end

  defp record_rate_limit(station_code) do
    key = rate_limit_key(station_code)
    :persistent_term.put(key, System.monotonic_time(:second))
  end

  defp rate_limit_key(station_code), do: {:order_manager_rate_limit, station_code}

  # --- Position Management ---

  defp find_or_create_position(station_code, market_cluster_id, label, token_id, price, amount) do
    case Repo.get_by(Position, station_code: station_code, market_cluster_id: market_cluster_id, outcome_label: label, status: "open") do
      nil ->
        {:ok, position} =
          %Position{}
          |> Position.changeset(%{
            station_code: station_code,
            market_cluster_id: market_cluster_id,
            outcome_label: label,
            side: "YES",
            token_id: token_id,
            tokens: 0.0,
            avg_buy_price: price,
            total_cost_usdc: amount,
            status: "open",
            opened_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.insert()

        position

      position ->
        position
    end
  end

  defp update_position_on_fill(order) do
    position = Repo.get(Position, order.position_id)

    if position do
      new_tokens = position.tokens + order.size
      new_total_cost = position.total_cost_usdc + order.usdc_amount
      new_avg_price = if new_tokens > 0, do: new_total_cost / new_tokens, else: position.avg_buy_price

      position
      |> Position.changeset(%{
        tokens: new_tokens,
        total_cost_usdc: new_total_cost,
        avg_buy_price: new_avg_price
      })
      |> Repo.update()
    end
  end

  # --- Retry Logic ---

  defp handle_order_failure(station_code, token_id, price, size, amount, outcome, reason) do
    retry_delay = trading_config()[:order_retry_delay_ms] || 30_000

    Logger.warning("Order failed for #{station_code}, retrying in #{retry_delay}ms: #{inspect(reason)}")

    Process.sleep(retry_delay)

    case ClobClient.place_order(token_id, "BUY", price, size) do
      {:ok, response} ->
        order_id = response["orderID"] || response["order_id"] || response["id"]
        label = outcome["outcome_label"]
        market_cluster_id = outcome["market_cluster_id"]

        position = find_or_create_position(station_code, market_cluster_id, label, token_id, price, amount)

        order_attrs = %{
          station_code: station_code,
          token_id: token_id,
          order_id: order_id,
          side: "BUY",
          price: price,
          size: size,
          usdc_amount: amount,
          status: "pending",
          auto_order: Map.get(outcome, "auto_order", false),
          placed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          position_id: position.id
        }

        {:ok, order} =
          %Order{}
          |> Order.changeset(order_attrs)
          |> Repo.insert()

        record_rate_limit(station_code)
        Logger.info("Order placed on retry: #{order.id}")
        broadcast(:order_placed, order)
        schedule_fill_check(order)

        {:ok, order}

      {:error, retry_reason} ->
        error_msg = "Failed after retry: #{inspect(retry_reason)} (original: #{inspect(reason)})"
        Logger.error("Order permanently failed for #{station_code}: #{error_msg}")

        order_attrs = %{
          station_code: station_code,
          token_id: token_id,
          side: "BUY",
          price: price,
          size: size,
          usdc_amount: amount,
          status: "failed",
          error_message: error_msg,
          placed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        {:ok, order} =
          %Order{}
          |> Order.changeset(order_attrs)
          |> Repo.insert()

        broadcast(:order_failed, order)

        {:error, {:order_failed, error_msg}}
    end
  end

  defp schedule_fill_check(%Order{order_id: order_id} = order) when is_binary(order_id) do
    Task.start(fn ->
      Process.sleep(5_000)
      check_order_fill(order)
    end)
  end

  defp schedule_fill_check(_order), do: :ok

  defp check_order_fill(%Order{} = order) do
    order = Repo.get(Order, order.id)

    if order && order.status == "pending" do
      case ClobClient.get_open_orders() do
        {:ok, open_orders} ->
          still_open = Enum.any?(open_orders, fn o ->
            (o["id"] || o["orderID"]) == order.order_id
          end)

          unless still_open do
            mark_filled(order)
          end

        {:error, _reason} ->
          :ok
      end
    end
  end

  # --- PubSub ---

  defp broadcast(event, order) do
    topic = PubSubHelper.station_auto_buy(order.station_code)
    PubSubHelper.broadcast(topic, {event, order})
  end

  # --- Config ---

  defp trading_config do
    Application.get_env(:weather_edge, :trading, [])
  end
end
