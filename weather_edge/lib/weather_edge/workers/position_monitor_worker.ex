defmodule WeatherEdge.Workers.PositionMonitorWorker do
  @moduledoc """
  Monitors open positions every 10 minutes, updating P&L and
  generating sell/hold recommendations for each.
  """

  use Oban.Worker, queue: :signals

  require Logger

  import Ecto.Query

  alias WeatherEdge.Repo
  alias WeatherEdge.Trading.{Position, PositionTracker}
  alias WeatherEdge.PubSubHelper

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    positions = open_positions()

    Logger.info("PositionMonitorWorker: Monitoring #{length(positions)} open position(s)")

    Enum.each(positions, fn position ->
      monitor_position(position)
    end)

    WeatherEdge.JobTracker.record(:position_monitor)
    :ok
  end

  defp open_positions do
    Position
    |> where([p], p.status == "open")
    |> Repo.all()
  end

  defp monitor_position(position) do
    with {:ok, updated} <- PositionTracker.update_position(position),
         {:ok, updated} <- PositionTracker.generate_recommendation(updated) do
      PubSubHelper.broadcast(
        PubSubHelper.portfolio_position_update(),
        {:position_updated, updated}
      )

      Logger.debug("PositionMonitorWorker: Updated position #{position.id} - recommendation: #{updated.recommendation}")
    else
      {:error, reason} ->
        Logger.warning("PositionMonitorWorker: Failed to update position #{position.id}: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.error("PositionMonitorWorker: Error monitoring position #{position.id}: #{Exception.message(e)}")
  end
end
