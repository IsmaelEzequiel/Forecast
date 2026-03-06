defmodule WeatherEdge.Calibration.Resolver do
  @moduledoc """
  Processes market resolution by comparing predicted distributions against actual temperatures.
  Calculates per-model forecast errors and stores ForecastAccuracy records.
  """

  alias WeatherEdge.Repo
  alias WeatherEdge.Forecasts
  alias WeatherEdge.Probability.{Distribution, Engine}
  alias WeatherEdge.Calibration.Accuracy
  alias WeatherEdge.Trading.Position

  import Ecto.Query

  @doc """
  Processes a resolution for a market cluster given the actual temperature.

  1. Computes predicted distribution from latest forecasts
  2. Calculates per-model absolute error
  3. Determines if the top predicted outcome matched the actual temp
  4. Tracks auto-buy outcome and P&L if applicable
  5. Stores a ForecastAccuracy record
  """
  @spec process_resolution(map(), integer()) :: {:ok, Accuracy.t()} | {:error, term()}
  def process_resolution(market_cluster, actual_temp) do
    station_code = market_cluster.station_code
    target_date = market_cluster.target_date

    with {:ok, distribution} <- Engine.compute_distribution(station_code, target_date),
         model_errors <- compute_model_errors(station_code, target_date, actual_temp),
         resolution_correct <- resolution_correct?(distribution, actual_temp),
         {auto_buy_outcome, auto_buy_pnl} <- compute_auto_buy_stats(market_cluster) do
      attrs = %{
        station_code: station_code,
        target_date: target_date,
        predicted_distribution: distribution.probabilities,
        actual_temp: actual_temp,
        model_errors: model_errors,
        resolution_correct: resolution_correct,
        auto_buy_outcome: auto_buy_outcome,
        auto_buy_pnl: auto_buy_pnl
      }

      %Accuracy{}
      |> Accuracy.changeset(attrs)
      |> Repo.insert()
    end
  end

  defp compute_model_errors(station_code, target_date, actual_temp) do
    snapshots = Forecasts.latest_snapshots(station_code, target_date)

    Map.new(snapshots, fn snapshot ->
      error = snapshot.max_temp_c - actual_temp
      {snapshot.model, %{error: error, absolute_error: abs(error), predicted: snapshot.max_temp_c}}
    end)
  end

  defp resolution_correct?(%Distribution{} = distribution, actual_temp) do
    case Distribution.top_outcome(distribution) do
      nil ->
        false

      {top_label, _prob} ->
        actual_label = "#{actual_temp}C"

        cond do
          top_label == actual_label ->
            true

          String.contains?(top_label, "or below") ->
            case Regex.run(~r/(\d+)/, top_label) do
              [_, threshold] -> actual_temp <= String.to_integer(threshold)
              _ -> false
            end

          String.contains?(top_label, "or higher") ->
            case Regex.run(~r/(\d+)/, top_label) do
              [_, threshold] -> actual_temp >= String.to_integer(threshold)
              _ -> false
            end

          true ->
            false
        end
    end
  end

  defp compute_auto_buy_stats(market_cluster) do
    positions =
      Position
      |> where(
        [p],
        p.market_cluster_id == ^market_cluster.id and p.auto_bought == true
      )
      |> Repo.all()

    case positions do
      [] ->
        {nil, nil}

      positions ->
        total_pnl =
          positions
          |> Enum.map(fn p -> p.realized_pnl || 0.0 end)
          |> Enum.sum()

        outcome =
          cond do
            Enum.any?(positions, &(&1.status == "sold")) -> "sold_early"
            total_pnl > 0 -> "win"
            true -> "loss"
          end

        {outcome, total_pnl}
    end
  end
end
