defmodule WeatherEdge.Stations do
  @moduledoc """
  Context for managing weather stations.
  """

  import Ecto.Query
  alias WeatherEdge.Repo
  alias WeatherEdge.Stations.Station
  alias WeatherEdge.Forecasts.MetarClient

  @pubsub WeatherEdge.PubSub
  @topic "stations"

  def list_stations do
    Repo.all(from s in Station, order_by: s.code)
  end

  def get_station(id) do
    case Repo.get(Station, id) do
      nil -> {:error, :not_found}
      station -> {:ok, station}
    end
  end

  def get_by_code(code) do
    case Repo.get_by(Station, code: code) do
      nil -> {:error, :not_found}
      station -> {:ok, station}
    end
  end

  def create_station(%{"code" => code} = _attrs) do
    create_station_with_code(String.upcase(code))
  end

  def create_station(%{code: code} = _attrs) do
    create_station_with_code(String.upcase(code))
  end

  defp create_station_with_code(code) do
    case MetarClient.validate_station(code) do
      {:ok, info} ->
        attrs =
          info
          |> Map.put(:monitoring_enabled, true)
          |> Map.put(:auto_buy_enabled, false)
          |> Map.put(:max_buy_price, 0.20)
          |> Map.put(:buy_amount_usdc, 5.00)
          |> Map.put(:slug_pattern, generate_slug_pattern(info.city))

        %Station{}
        |> Station.changeset(attrs)
        |> Repo.insert()
        |> tap_broadcast(:station_created)

      {:error, :invalid_station} ->
        {:error, :invalid_station}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_station(%Station{} = station, attrs) do
    station
    |> Station.changeset(attrs)
    |> Repo.update()
    |> tap_broadcast(:station_updated)
  end

  def delete_station(%Station{} = station) do
    station
    |> Repo.delete()
    |> tap_broadcast(:station_deleted)
  end

  defp generate_slug_pattern(nil), do: nil

  defp generate_slug_pattern(city) do
    slug =
      city
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    "highest-temperature-in-#{slug}-on-*"
  end

  defp tap_broadcast({:ok, station} = result, event) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {event, station})
    result
  end

  defp tap_broadcast(error, _event), do: error
end
