defmodule WeatherEdge.Signals.Alerter do
  @moduledoc """
  Broadcasts signal alerts via PubSub to station-specific topics.
  """

  alias WeatherEdge.PubSubHelper

  @doc """
  Broadcasts a list of signals for a station via PubSub.
  """
  @spec broadcast_signals(String.t(), [map()], Date.t() | nil) :: :ok
  def broadcast_signals(station_code, signals, target_date \\ nil) when is_binary(station_code) do
    topic = PubSubHelper.station_signal(station_code)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(signals, fn signal ->
      enriched =
        signal
        |> Map.put(:station_code, station_code)
        |> Map.put(:computed_at, now)
        |> Map.put(:target_date, target_date)
        |> Map.put_new_lazy(:market_price, fn ->
          Map.get(signal, :market_yes_price, Map.get(signal, :market_price))
        end)

      PubSubHelper.broadcast(topic, {:signal_detected, enriched})
    end)

    :ok
  end
end
