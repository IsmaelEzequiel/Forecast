defmodule WeatherEdge.Forecasts.ForecastSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forecast_snapshots" do
    field :fetched_at, :utc_datetime
    field :target_date, :date
    field :model, :string
    field :max_temp_c, :float
    field :hourly_temps, :map

    belongs_to :station, WeatherEdge.Stations.Station,
      foreign_key: :station_code,
      references: :code,
      type: :string
  end

  @required_fields ~w(station_code fetched_at target_date model max_temp_c)a
  @optional_fields ~w(hourly_temps)a

  def changeset(forecast_snapshot, attrs) do
    forecast_snapshot
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:model, max: 20)
    |> foreign_key_constraint(:station_code)
  end
end
