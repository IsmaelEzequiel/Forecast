defmodule WeatherEdge.Workers.BalanceWorker do
  @moduledoc """
  Refreshes USDC balance every 5 minutes and broadcasts via PubSub.
  """

  use Oban.Worker, queue: :trading

  require Logger

  alias WeatherEdge.Trading.DataClient
  alias WeatherEdge.PubSubHelper

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case DataClient.get_balance() do
      {:ok, balance} ->
        PubSubHelper.broadcast(
          PubSubHelper.portfolio_balance_update(),
          {:balance_updated, balance}
        )

        Logger.debug("BalanceWorker: USDC balance refreshed: #{balance}")

      {:error, reason} ->
        Logger.warning("BalanceWorker: Failed to fetch balance: #{inspect(reason)}")
    end

    :ok
  end
end
