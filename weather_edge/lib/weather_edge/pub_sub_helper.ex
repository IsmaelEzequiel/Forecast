defmodule WeatherEdge.PubSubHelper do
  @moduledoc """
  Centralized PubSub helper defining all topics and broadcast/subscribe functions.
  """

  @pubsub WeatherEdge.PubSub

  # Topic functions

  def station_new_event(code), do: "station:#{code}:new_event"
  def station_forecast_update(code), do: "station:#{code}:forecast_update"
  def station_price_update(code), do: "station:#{code}:price_update"
  def station_auto_buy(code), do: "trading:#{code}"
  def station_signal(code), do: "station:#{code}:signal"
  def stations, do: "stations"

  def portfolio_balance_update, do: "portfolio:balance_update"
  def portfolio_position_update, do: "portfolio:position_update"
  def signals_new, do: "signals:new"

  # Dutch position topics
  def dutch_price_update, do: "dutch:price_update"
  def dutch_new_position, do: "dutch:new_position"
  def dutch_sold, do: "dutch:sold"
  def dutch_resolved, do: "dutch:resolved"

  # Broadcast and subscribe wrappers

  def broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end

  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub, topic)
  end
end
