defmodule WeatherEdge.Stations.Station do
  use Ecto.Schema
  import Ecto.Changeset

  schema "stations" do
    field :code, :string
    field :city, :string
    field :latitude, :float
    field :longitude, :float
    field :country, :string
    field :wunderground_url, :string
    field :monitoring_enabled, :boolean, default: true
    field :auto_buy_enabled, :boolean, default: false
    field :max_buy_price, :float, default: 0.20
    field :buy_amount_usdc, :float, default: 5.00
    field :slug_pattern, :string
    field :tag_slug, :string
    field :temp_unit, :string, default: "C"

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(code city latitude longitude country)a
  @optional_fields ~w(wunderground_url monitoring_enabled auto_buy_enabled max_buy_price buy_amount_usdc slug_pattern tag_slug temp_unit)a

  def changeset(station, attrs) do
    station
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:code, ~r/^[A-Z]{3,4}$/, message: "must be 3-4 uppercase letters")
    |> unique_constraint(:code)
  end
end
