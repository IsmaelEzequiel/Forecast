defmodule WeatherEdge.Signals.DetailData do
  @moduledoc false

  import Ecto.Query

  alias WeatherEdge.Repo
  alias WeatherEdge.Signals.Signal
  alias WeatherEdge.Markets.MarketCluster
  alias WeatherEdge.Stations.Station
  alias WeatherEdge.Trading.Position
  alias WeatherEdge.Probability.Engine
  alias WeatherEdge.Forecasts
  alias WeatherEdge.Forecasts.MetarClient
  alias WeatherEdge.Trading.ClobClient

  def fetch_signal_detail(signal_id) do
    case load_signal_with_joins(signal_id) do
      nil ->
        nil

      %{signal: signal, cluster: cluster} = base ->
        distribution = fetch_distribution(signal.station_code, cluster.target_date)
        model_breakdown = fetch_model_breakdown(signal.station_code, cluster.target_date)
        orderbook = fetch_orderbook(cluster.outcomes, signal.outcome_label)
        metar = fetch_metar(signal.station_code, cluster.target_date)
        balance = :persistent_term.get(:sidecar_balance, nil)

        Map.merge(base, %{
          distribution: distribution,
          model_breakdown: model_breakdown,
          orderbook: orderbook,
          metar: metar,
          balance: balance
        })
    end
  end

  defp load_signal_with_joins(signal_id) do
    query =
      from s in Signal,
        join: mc in MarketCluster,
        on: mc.id == s.market_cluster_id,
        join: st in Station,
        on: st.code == s.station_code,
        left_join: p in Position,
        on:
          p.market_cluster_id == s.market_cluster_id and
            p.outcome_label == s.outcome_label and
            p.status == "open",
        where: s.id == ^signal_id,
        select: %{
          signal: s,
          cluster: mc,
          station: st,
          position: p
        }

    Repo.one(query)
  end

  defp fetch_distribution(station_code, target_date) do
    case Engine.compute_distribution(station_code, target_date) do
      {:ok, distribution} -> distribution
      _ -> nil
    end
  end

  defp fetch_model_breakdown(station_code, target_date) do
    Forecasts.latest_snapshots(station_code, target_date)
  end

  defp fetch_orderbook(outcomes, outcome_label) do
    token_id = find_token_id(outcomes, outcome_label)

    if token_id do
      case ClobClient.get_orderbook(token_id) do
        {:ok, orderbook} -> parse_orderbook(orderbook)
        _ -> nil
      end
    else
      nil
    end
  end

  defp parse_orderbook(%{bids: bids, asks: asks}) do
    best_bid = List.first(bids)
    best_ask = List.first(asks)

    spread =
      if best_bid && best_ask do
        ask_price = parse_price(best_ask["price"])
        bid_price = parse_price(best_bid["price"])
        ask_price - bid_price
      end

    %{
      best_bid: best_bid,
      best_ask: best_ask,
      spread: spread
    }
  end

  defp parse_orderbook(%{"bids" => bids, "asks" => asks}) do
    parse_orderbook(%{bids: bids, asks: asks})
  end

  defp parse_orderbook(_), do: nil

  defp parse_price(price) when is_binary(price) do
    case Float.parse(price) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_price(price) when is_number(price), do: price * 1.0
  defp parse_price(_), do: 0.0

  defp fetch_metar(station_code, target_date) do
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)

    if target_date == today or target_date == tomorrow do
      conditions =
        case MetarClient.get_current_conditions(station_code) do
          {:ok, data} -> data
          _ -> nil
        end

      todays_high =
        case MetarClient.get_todays_high(station_code) do
          {:ok, temp} -> temp
          _ -> nil
        end

      if conditions || todays_high do
        %{conditions: conditions, todays_high: todays_high}
      end
    end
  end

  defp find_token_id(outcomes, outcome_label) when is_list(outcomes) do
    case Enum.find(outcomes, fn o ->
           o["outcome_label"] == outcome_label || o["label"] == outcome_label
         end) do
      %{"token_id" => token_id} -> token_id
      _ -> nil
    end
  end

  defp find_token_id(outcomes, outcome_label) when is_map(outcomes) do
    case Map.get(outcomes, outcome_label) do
      %{"token_id" => token_id} -> token_id
      _ -> nil
    end
  end

  defp find_token_id(_, _), do: nil
end
