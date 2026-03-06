defmodule WeatherEdge.Signals.Alerter do
  @moduledoc """
  Broadcasts signal alerts via PubSub to station-specific topics.
  """

  @pubsub WeatherEdge.PubSub

  @doc """
  Broadcasts a list of signals for a station via PubSub.
  Topic format: "station:CODE:signal"
  """
  @spec broadcast_signals(String.t(), [map()]) :: :ok
  def broadcast_signals(station_code, signals) when is_binary(station_code) do
    topic = "station:#{station_code}:signal"

    Enum.each(signals, fn signal ->
      Phoenix.PubSub.broadcast(@pubsub, topic, {:signal_detected, signal})
    end)

    :ok
  end
end
