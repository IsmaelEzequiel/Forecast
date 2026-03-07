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
    # Prefer sidecar balance (synced via /sync endpoint), fall back to Data API
    case get_balance() do
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

  defp get_balance do
    case :persistent_term.get(:sidecar_balance, nil) do
      balance when is_number(balance) -> {:ok, balance}
      _ -> DataClient.get_balance()
    end
  end
end
