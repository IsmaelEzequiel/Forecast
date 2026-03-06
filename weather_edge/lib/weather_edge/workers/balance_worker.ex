defmodule WeatherEdge.Workers.BalanceWorker do
  @moduledoc """
  Refreshes USDC balance every 5 minutes and broadcasts via PubSub.
  """

  use Oban.Worker, queue: :trading

  require Logger

  alias WeatherEdge.Trading.DataClient

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case DataClient.get_balance() do
      {:ok, balance} ->
        Phoenix.PubSub.broadcast(
          WeatherEdge.PubSub,
          "portfolio:balance_update",
          {:balance_updated, balance}
        )

        Logger.debug("BalanceWorker: USDC balance refreshed: #{balance}")

      {:error, reason} ->
        Logger.warning("BalanceWorker: Failed to fetch balance: #{inspect(reason)}")
    end

    :ok
  end
end
