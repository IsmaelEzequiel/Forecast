defmodule WeatherEdge.Trading.PositionTracker do
  @moduledoc """
  Tracks open positions, calculates P&L, and generates
  data-driven sell/hold recommendations.
  """

  require Logger

  alias WeatherEdge.Repo
  alias WeatherEdge.Trading.Position
  alias WeatherEdge.Probability.Engine
  alias WeatherEdge.PubSubHelper

  @doc """
  Fetches current YES price from CLOB and updates unrealized P&L on the position.

  Returns `{:ok, position}` or `{:error, reason}`.
  """
  @spec update_position(Position.t()) :: {:ok, Position.t()} | {:error, term()}
  def update_position(%Position{} = position) do
    case clob_client().get_price(position.token_id, "sell") do
      {:ok, current_price} ->
        unrealized_pnl = (current_price - position.avg_buy_price) * position.tokens
        unrealized_pnl_pct = if position.avg_buy_price > 0, do: unrealized_pnl / position.total_cost_usdc * 100, else: 0.0

        {:ok, updated} =
          position
          |> Position.changeset(%{
            current_price: current_price,
            unrealized_pnl: unrealized_pnl
          })
          |> Repo.update()

        {:ok, Map.put(updated, :unrealized_pnl_pct, unrealized_pnl_pct)}

      {:error, reason} ->
        Logger.warning("Failed to fetch price for position #{position.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generates a sell/hold recommendation based on P&L, model probability,
  and days until resolution.

  Recommendation logic:
    - pnl >= 100% AND model_prob < 0.40 -> "SELL NOW"
    - pnl >= 75% AND days_until_resolution <= 1 -> "CONSIDER SELLING"
    - pnl >= 50% AND model_prob > 0.50 -> "HOLD"
    - pnl < 20% AND model_prob < 0.20 -> "CUT LOSS"
    - model_prob > 0.60 AND days_until_resolution == 0 -> "HOLD TO RESOLUTION"
    - default -> "MONITORING"

  Returns `{:ok, position}` with updated recommendation.
  """
  @spec generate_recommendation(Position.t()) :: {:ok, Position.t()} | {:error, term()}
  def generate_recommendation(%Position{} = position) do
    position = Repo.preload(position, :market_cluster)
    cluster = position.market_cluster

    unless cluster do
      {:error, :no_market_cluster}
    else
      days_until = Date.diff(cluster.target_date, Date.utc_today())
      pnl_pct = calculate_pnl_pct(position)
      model_prob = get_model_probability(position.station_code, cluster.target_date, position.outcome_label)

      recommendation = determine_recommendation(pnl_pct, model_prob, days_until)

      {:ok, updated} =
        position
        |> Position.changeset(%{
          current_price: position.current_price,
          unrealized_pnl: position.unrealized_pnl,
          recommendation: recommendation
        })
        |> Repo.update()

      {:ok, updated}
    end
  end

  @doc """
  Places a sell order via OrderManager and updates the position status to "sold".

  Returns `{:ok, position}` or `{:error, reason}`.
  """
  @spec sell_position(Position.t()) :: {:ok, Position.t()} | {:error, term()}
  def sell_position(%Position{status: "open"} = position) do
    sell_price = position.current_price || position.avg_buy_price

    case clob_client().place_order(position.token_id, "SELL", sell_price, position.tokens) do
      {:ok, response} ->
        order_id = response["orderID"] || response["order_id"] || response["id"]

        order_attrs = %{
          station_code: position.station_code,
          token_id: position.token_id,
          order_id: order_id,
          side: "SELL",
          price: sell_price,
          size: position.tokens,
          usdc_amount: sell_price * position.tokens,
          status: "pending",
          position_id: position.id,
          placed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        {:ok, _order} =
          %WeatherEdge.Trading.Order{}
          |> WeatherEdge.Trading.Order.changeset(order_attrs)
          |> Repo.insert()

        realized_pnl = (sell_price - position.avg_buy_price) * position.tokens

        {:ok, updated} =
          position
          |> Position.changeset(%{
            status: "sold",
            close_price: sell_price,
            realized_pnl: realized_pnl,
            closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
          |> Repo.update()

        Logger.info("Position #{position.id} sold at #{sell_price}, realized P&L: #{realized_pnl}")
        {:ok, updated}

      {:error, reason} ->
        Logger.warning("Failed to sell position #{position.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def sell_position(%Position{status: status}) do
    {:error, {:invalid_status, status}}
  end

  @doc """
  Reconciles DB positions with live Polymarket positions from the sidecar.
  Positions that are open in the DB but no longer on Polymarket are marked as closed.
  Returns the list of positions that were closed.
  """
  @spec reconcile_with_sidecar([map()]) :: [Position.t()]
  def reconcile_with_sidecar(sidecar_positions) do
    import Ecto.Query

    # Build a set of asset IDs that are still open on Polymarket
    # Only count positions with non-zero size as "still open"
    live_asset_ids =
      sidecar_positions
      |> Enum.filter(fn p ->
        size = p["size"] || p["currentValue"]
        is_number(size) and size > 0
      end)
      |> Enum.flat_map(fn p ->
        [p["asset"] || p["assetId"] || p["token_id"]]
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    # Find DB positions that are "open" but no longer on Polymarket
    db_open_positions =
      Position
      |> where([p], p.status == "open")
      |> Repo.all()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.reduce(db_open_positions, [], fn position, closed ->
      if MapSet.member?(live_asset_ids, position.token_id) do
        closed
      else
        # Position no longer on Polymarket — it was sold or resolved
        # For won markets (resolved YES), close_price = 1.0
        # For sold positions, we use the last known current_price
        close_price = position.current_price || position.avg_buy_price
        realized_pnl = (close_price - position.avg_buy_price) * position.tokens

        case position
             |> Position.changeset(%{
               status: "closed",
               close_price: close_price,
               realized_pnl: realized_pnl,
               closed_at: now
             })
             |> Repo.update() do
          {:ok, updated} ->
            Logger.info(
              "Position #{position.id} reconciled as closed — realized P&L: #{realized_pnl}"
            )

            PubSubHelper.broadcast(
              PubSubHelper.portfolio_position_update(),
              {:position_updated, updated}
            )

            [updated | closed]

          {:error, _} ->
            closed
        end
      end
    end)
  end

  # --- Private ---

  defp calculate_pnl_pct(%Position{total_cost_usdc: cost, unrealized_pnl: pnl})
       when is_number(cost) and is_number(pnl) and cost > 0 do
    pnl / cost * 100
  end

  defp calculate_pnl_pct(%Position{avg_buy_price: avg, current_price: current})
       when is_number(avg) and is_number(current) and avg > 0 do
    (current - avg) / avg * 100
  end

  defp calculate_pnl_pct(_position), do: 0.0

  defp get_model_probability(station_code, target_date, outcome_label) do
    case Engine.compute_distribution(station_code, target_date) do
      {:ok, distribution} ->
        WeatherEdge.Probability.Distribution.probability_for(distribution, outcome_label)

      {:error, _} ->
        0.0
    end
  end

  defp determine_recommendation(pnl_pct, model_prob, days_until) do
    cond do
      pnl_pct >= 100 and model_prob < 0.40 -> "SELL NOW"
      pnl_pct >= 75 and days_until <= 1 -> "CONSIDER SELLING"
      pnl_pct >= 50 and model_prob > 0.50 -> "HOLD"
      pnl_pct < 20 and model_prob < 0.20 -> "CUT LOSS"
      model_prob > 0.60 and days_until == 0 -> "HOLD TO RESOLUTION"
      true -> "MONITORING"
    end
  end

  defp clob_client, do: Application.get_env(:weather_edge, :clob_client, WeatherEdge.Trading.ClobClient)
end
