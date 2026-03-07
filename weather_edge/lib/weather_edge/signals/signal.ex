defmodule WeatherEdge.Signals.Signal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "signals" do
    field :computed_at, :utc_datetime
    field :outcome_label, :string
    field :model_probability, :float
    field :market_price, :float
    field :edge, :float
    field :recommended_side, :string
    field :alert_level, :string
    field :confidence, :string

    field :station_code, :string
    belongs_to :market_cluster, WeatherEdge.Markets.MarketCluster
  end

  @required_fields ~w(station_code market_cluster_id computed_at outcome_label model_probability market_price edge recommended_side)a
  @optional_fields ~w(alert_level confidence)a

  def changeset(signal, attrs) do
    signal
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:station_code, max: 4)
    |> validate_length(:outcome_label, max: 255)
    |> validate_length(:recommended_side, max: 3)
    |> validate_length(:alert_level, max: 20)
    |> foreign_key_constraint(:market_cluster_id)
  end
end
