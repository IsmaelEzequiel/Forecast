defmodule WeatherEdge.Forecasts do
  @moduledoc """
  Context for weather forecast data management.
  Stores and retrieves forecast snapshots from multiple weather models.
  """

  import Ecto.Query
  alias WeatherEdge.Repo
  alias WeatherEdge.Forecasts.ForecastSnapshot

  @doc """
  Stores a forecast snapshot record.
  Accepts a map with station_code, fetched_at, target_date, model, max_temp_c, and optional hourly_temps.
  """
  @spec store_snapshot(map()) :: {:ok, ForecastSnapshot.t()} | {:error, Ecto.Changeset.t()}
  def store_snapshot(attrs) do
    %ForecastSnapshot{}
    |> ForecastSnapshot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists forecast snapshots for a station and target date.
  """
  def list_snapshots(station_code, target_date) do
    ForecastSnapshot
    |> where([f], f.station_code == ^station_code and f.target_date == ^target_date)
    |> order_by([f], desc: f.fetched_at)
    |> Repo.all()
  end

  @doc """
  Gets the latest forecast snapshot per model for a station and target date.
  """
  def latest_snapshots(station_code, target_date) do
    ForecastSnapshot
    |> where([f], f.station_code == ^station_code and f.target_date == ^target_date)
    |> distinct([f], f.model)
    |> order_by([f], [f.model, desc: f.fetched_at])
    |> Repo.all()
  end
end
