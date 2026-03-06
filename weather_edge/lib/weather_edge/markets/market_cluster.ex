defmodule WeatherEdge.Markets.MarketCluster do
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_clusters" do
    field :event_id, :string
    field :event_slug, :string
    field :target_date, :date
    field :title, :string
    field :outcomes, {:array, :map}
    field :resolved, :boolean, default: false
    field :resolution_temp, :integer

    belongs_to :station, WeatherEdge.Stations.Station,
      foreign_key: :station_code,
      references: :code,
      type: :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(event_id event_slug target_date outcomes)a
  @optional_fields ~w(station_code title resolved resolution_temp)a

  def changeset(market_cluster, attrs) do
    market_cluster
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:event_id)
    |> foreign_key_constraint(:station_code)
  end
end
