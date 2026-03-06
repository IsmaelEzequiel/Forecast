defmodule WeatherEdge.Workers.AutoBuyerWorker do
  @moduledoc """
  Automatically buys the most likely temperature outcome when a new event opens.
  Enqueued by EventScannerWorker when a station has auto_buy_enabled=true.
  """

  use Oban.Worker, queue: :trading

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"station_code" => station_code, "event_id" => event_id}}) do
    Logger.info("AutoBuyer: Placeholder for #{station_code} event #{event_id}")
    :ok
  end
end
