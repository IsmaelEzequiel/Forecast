defmodule WeatherEdge.Workers.AutoBuyerWorker do
  @moduledoc """
  Automatically buys the most likely temperature outcome when a new event opens.
  Enqueued by EventScannerWorker when a station has auto_buy_enabled=true.
  """

  use Oban.Worker, queue: :trading

  require Logger

  alias WeatherEdge.Forecasts
  alias WeatherEdge.Forecasts.OpenMeteoClient
  alias WeatherEdge.Markets
  alias WeatherEdge.Probability.{Distribution, Engine}
  alias WeatherEdge.Stations
  alias WeatherEdge.Trading.OrderManager
  alias WeatherEdge.PubSubHelper

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"station_code" => station_code, "event_id" => event_id}}) do
    with {:ok, station} <- Stations.get_by_code(station_code),
         cluster when not is_nil(cluster) <- Markets.get_by_event_id(event_id) do
      run_auto_buy(station, cluster)
    else
      {:error, :not_found} ->
        Logger.error("AutoBuyer: Station #{station_code} not found")
        :ok

      nil ->
        Logger.error("AutoBuyer: Event #{event_id} not found")
        :ok
    end
  end

  defp run_auto_buy(station, cluster) do
    # Check peak status — only auto-buy today's markets on confirmed/high confidence
    {peak_status, _} = WeatherEdge.Timezone.PeakCalculator.peak_status(station.longitude)
    confidence = WeatherEdge.Timezone.PeakCalculator.confidence(peak_status)

    if confidence == :forecast and cluster.target_date == Date.utc_today() do
      Logger.info(
        "AutoBuyer: Skipping #{station.code} — pre-peak, forecast-only confidence"
      )
    else
      run_auto_buy_execution(station, cluster)
    end
  end

  defp run_auto_buy_execution(station, cluster) do
    with :ok <- fetch_and_store_forecasts(station, cluster.target_date),
         {:ok, distribution} <- Engine.compute_distribution(station.code, cluster.target_date) do
      {top_label, top_prob} = Distribution.top_outcome(distribution)

      Logger.info(
        "AutoBuyer: #{station.code} top outcome=#{top_label} prob=#{Float.round(top_prob * 100, 1)}%"
      )

      outcome_data = find_outcome_in_cluster(cluster, top_label)

      case outcome_data do
        nil ->
          Logger.warning("AutoBuyer: Outcome #{top_label} not found in cluster #{cluster.event_id}")
          :ok

        outcome ->
          handle_top_outcome(station, cluster, outcome, top_prob, distribution)
      end
    else
      {:error, :no_forecasts} ->
        Logger.warning("AutoBuyer: No forecasts available for #{station.code}")
        :ok

      {:error, reason} ->
        Logger.error("AutoBuyer: Failed for #{station.code}: #{inspect(reason)}")
        :ok
    end
  end

  defp handle_top_outcome(station, cluster, outcome, top_prob, distribution) do
    token_id = outcome["clob_token_ids"] |> List.wrap() |> List.first()

    case clob_client().get_price(token_id, "buy") do
      {:ok, yes_price} ->
        if yes_price <= station.max_buy_price do
          execute_buy(station, cluster, outcome, token_id, yes_price, top_prob)
        else
          Logger.info(
            "AutoBuyer: Skipping #{station.code} - YES price #{yes_price} > max #{station.max_buy_price}"
          )

          broadcast_skipped(station.code, cluster, outcome, yes_price)
        end

        check_secondary_opportunities(station, cluster, distribution, outcome["outcome_label"])
        :ok

      {:error, reason} ->
        Logger.error("AutoBuyer: Failed to get price for #{station.code}: #{inspect(reason)}")
        :ok
    end
  end

  defp execute_buy(station, cluster, outcome, token_id, yes_price, model_prob) do
    order_outcome = %{
      "token_id" => token_id,
      "outcome_label" => outcome["outcome_label"],
      "price" => yes_price,
      "market_cluster_id" => cluster.id,
      "event_id" => cluster.event_id,
      "auto_order" => true
    }

    case OrderManager.place_buy_order(station.code, order_outcome, station.buy_amount_usdc) do
      {:ok, order} ->
        Logger.info(
          "AutoBuyer: Bought #{outcome["outcome_label"]} for #{station.code} " <>
            "at $#{yes_price} (model prob: #{Float.round(model_prob * 100, 1)}%)"
        )

        broadcast_executed(station.code, cluster, outcome, order, yes_price, model_prob)

      {:error, reason} ->
        Logger.warning("AutoBuyer: Buy failed for #{station.code}: #{inspect(reason)}")
    end
  end

  defp check_secondary_opportunities(station, cluster, distribution, primary_label) do
    outcomes = cluster.outcomes || []

    Enum.each(outcomes, fn outcome ->
      label = outcome["outcome_label"]

      if label != primary_label do
        model_prob = Distribution.probability_for(distribution, label)

        if model_prob > 0.20 do
          token_id = outcome["clob_token_ids"] |> List.wrap() |> List.first()

          case clob_client().get_price(token_id, "buy") do
            {:ok, yes_price} when yes_price <= station.max_buy_price ->
              Logger.info(
                "AutoBuyer: Secondary opportunity for #{station.code}: " <>
                  "#{label} at $#{yes_price} (model: #{Float.round(model_prob * 100, 1)}%)"
              )

              broadcast_secondary_alert(station.code, cluster, label, yes_price, model_prob)

            _ ->
              :ok
          end
        end
      end
    end)
  end

  defp fetch_and_store_forecasts(station, target_date) do
    case OpenMeteoClient.fetch_all_models(station.latitude, station.longitude) do
      {:ok, api_response} ->
        daily_maxes = OpenMeteoClient.extract_daily_max(api_response, target_date)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Enum.each(daily_maxes, fn {model, max_temp} ->
          Forecasts.store_snapshot(%{
            station_code: station.code,
            target_date: target_date,
            model: model,
            max_temp_c: max_temp,
            fetched_at: now
          })
        end)

        :ok

      {:error, reason} ->
        {:error, {:forecast_fetch_failed, reason}}
    end
  end

  defp find_outcome_in_cluster(cluster, outcome_label) do
    outcomes = cluster.outcomes || []
    Enum.find(outcomes, fn o -> o["outcome_label"] == outcome_label end)
  end

  # --- PubSub Broadcasts ---

  defp broadcast_executed(station_code, cluster, outcome, order, price, model_prob) do
    PubSubHelper.broadcast(
      PubSubHelper.station_auto_buy(station_code),
      {:auto_buy_executed, %{
        station_code: station_code,
        event_id: cluster.event_id,
        outcome_label: outcome["outcome_label"],
        order_id: order.id,
        price: price,
        model_probability: model_prob,
        amount_usdc: order.usdc_amount
      }}
    )
  end

  defp broadcast_skipped(station_code, cluster, outcome, price) do
    PubSubHelper.broadcast(
      PubSubHelper.station_auto_buy(station_code),
      {:auto_buy_skipped, %{
        station_code: station_code,
        event_id: cluster.event_id,
        outcome_label: outcome["outcome_label"],
        yes_price: price,
        reason: :price_too_high
      }}
    )
  end

  defp clob_client, do: Application.get_env(:weather_edge, :clob_client, WeatherEdge.Trading.ClobClient)

  defp broadcast_secondary_alert(station_code, cluster, label, price, model_prob) do
    PubSubHelper.broadcast(
      PubSubHelper.station_auto_buy(station_code),
      {:secondary_opportunity, %{
        station_code: station_code,
        event_id: cluster.event_id,
        outcome_label: label,
        yes_price: price,
        model_probability: model_prob
      }}
    )
  end
end
