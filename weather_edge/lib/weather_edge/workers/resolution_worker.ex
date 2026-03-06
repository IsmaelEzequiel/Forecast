defmodule WeatherEdge.Workers.ResolutionWorker do
  @moduledoc """
  Daily worker that resolves expired market clusters by fetching actual temperatures
  from Weather Underground and finalizing position P&L.

  Runs daily at 11 PM ET via Oban cron (queue: :cleanup).
  """

  use Oban.Worker, queue: :cleanup

  require Logger

  import Ecto.Query

  alias WeatherEdge.Repo
  alias WeatherEdge.Markets
  alias WeatherEdge.Markets.MarketCluster
  alias WeatherEdge.Trading.Position
  alias WeatherEdge.Forecasts.WundergroundClient
  alias WeatherEdge.Stations
  alias WeatherEdge.Calibration.Resolver

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    clusters = get_unresolved_past_clusters(today)

    Logger.info("ResolutionWorker: Processing #{length(clusters)} expired cluster(s)")

    Enum.each(clusters, fn cluster ->
      resolve_cluster(cluster)
    end)

    :ok
  end

  defp get_unresolved_past_clusters(today) do
    MarketCluster
    |> where([mc], mc.resolved == false and mc.target_date < ^today)
    |> Repo.all()
  end

  defp resolve_cluster(cluster) do
    station = Stations.get_by_code(cluster.station_code)

    case fetch_actual_temp(cluster, station) do
      {:ok, actual_temp} ->
        {:ok, updated_cluster} = Markets.mark_resolved(cluster.id, actual_temp)
        resolve_positions(updated_cluster, actual_temp)
        process_calibration(updated_cluster, actual_temp)

        Logger.info(
          "ResolutionWorker: Resolved #{cluster.station_code} #{cluster.target_date} -> #{actual_temp}°C"
        )

      {:error, reason} ->
        Logger.warning(
          "ResolutionWorker: Failed to fetch actual temp for #{cluster.station_code} #{cluster.target_date}: #{inspect(reason)}"
        )
    end
  rescue
    e ->
      Logger.error(
        "ResolutionWorker: Error resolving cluster #{cluster.id}: #{Exception.message(e)}"
      )
  end

  defp fetch_actual_temp(cluster, _station) do
    WundergroundClient.get_actual_max_temp(cluster.station_code, cluster.target_date)
  end

  defp resolve_positions(cluster, actual_temp) do
    positions =
      Position
      |> where([p], p.market_cluster_id == ^cluster.id and p.status == "open")
      |> Repo.all()

    Enum.each(positions, fn position ->
      won = position_won?(position, cluster, actual_temp)

      status = if won, do: "resolved_win", else: "resolved_loss"

      realized_pnl =
        if won do
          # Winner gets 1.0 per token minus cost
          position.tokens * 1.0 - position.total_cost_usdc
        else
          # Loser gets nothing, loses total cost
          -position.total_cost_usdc
        end

      position
      |> Ecto.Changeset.change(%{
        status: status,
        realized_pnl: realized_pnl,
        close_price: if(won, do: 1.0, else: 0.0),
        closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      Logger.info(
        "ResolutionWorker: Position #{position.id} #{position.outcome_label} -> #{status} (P&L: #{realized_pnl})"
      )
    end)
  end

  defp position_won?(position, cluster, actual_temp) do
    winning_outcome = determine_winning_outcome(cluster.outcomes, actual_temp)
    position.outcome_label == winning_outcome && position.side == "YES"
  end

  defp process_calibration(cluster, actual_temp) do
    case Resolver.process_resolution(cluster, actual_temp) do
      {:ok, accuracy} ->
        Logger.info(
          "ResolutionWorker: Calibration recorded for #{cluster.station_code} #{cluster.target_date} (correct: #{accuracy.resolution_correct})"
        )

      {:error, reason} ->
        Logger.warning(
          "ResolutionWorker: Failed to record calibration for #{cluster.station_code} #{cluster.target_date}: #{inspect(reason)}"
        )
    end
  end

  @doc false
  def determine_winning_outcome(outcomes, actual_temp) when is_list(outcomes) do
    Enum.find_value(outcomes, fn outcome ->
      label = outcome["outcome_label"]

      cond do
        # Edge bucket: "26C or below"
        String.contains?(label, "or below") ->
          case Regex.run(~r/(\d+)/, label) do
            [_, threshold] ->
              if actual_temp <= String.to_integer(threshold), do: label

            _ ->
              nil
          end

        # Edge bucket: "34C or higher"
        String.contains?(label, "or higher") ->
          case Regex.run(~r/(\d+)/, label) do
            [_, threshold] ->
              if actual_temp >= String.to_integer(threshold), do: label

            _ ->
              nil
          end

        # Exact degree: "28C"
        true ->
          case Regex.run(~r/^(\d+)C$/, label) do
            [_, deg] ->
              if actual_temp == String.to_integer(deg), do: label

            _ ->
              nil
          end
      end
    end)
  end
end
