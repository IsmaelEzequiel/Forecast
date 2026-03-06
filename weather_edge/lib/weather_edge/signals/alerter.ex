defmodule WeatherEdge.Signals.Alerter do
  @moduledoc """
  Broadcasts signal alerts via PubSub to station-specific topics.
  """

  alias WeatherEdge.PubSubHelper

  @doc """
  Broadcasts a list of signals for a station via PubSub.
  """
  @spec broadcast_signals(String.t(), [map()]) :: :ok
  def broadcast_signals(station_code, signals) when is_binary(station_code) do
    topic = PubSubHelper.station_signal(station_code)

    Enum.each(signals, fn signal ->
      PubSubHelper.broadcast(topic, {:signal_detected, signal})
    end)

    :ok
  end
end
