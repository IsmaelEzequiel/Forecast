defmodule WeatherEdge.Markets.MarketSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "market_snapshots" do
    field :snapshot_at, :utc_datetime
    field :outcome_label, :string
    field :yes_price, :float
    field :no_price, :float
    field :volume, :float

    belongs_to :market_cluster, WeatherEdge.Markets.MarketCluster
  end

  @required_fields ~w(market_cluster_id snapshot_at outcome_label)a
  @optional_fields ~w(yes_price no_price volume)a

  def changeset(market_snapshot, attrs) do
    market_snapshot
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:outcome_label, max: 30)
    |> foreign_key_constraint(:market_cluster_id)
  end
end
