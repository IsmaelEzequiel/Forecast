defmodule WeatherEdge.Trading.DutchGroup do
  use Ecto.Schema
  import Ecto.Changeset

  schema "dutch_groups" do
    field :target_date, :date
    field :total_invested, :float
    field :guaranteed_payout, :float
    field :guaranteed_profit_pct, :float
    field :coverage, :float
    field :num_outcomes, :integer
    field :status, :string, default: "open"
    field :winning_outcome, :string
    field :actual_pnl, :float
    field :current_value, :float
    field :sell_recommendation, :string
    field :sell_reason, :string
    field :closed_at, :utc_datetime

    belongs_to :station, WeatherEdge.Stations.Station,
      foreign_key: :station_code,
      references: :code,
      type: :string

    belongs_to :market_cluster, WeatherEdge.Markets.MarketCluster

    has_many :dutch_orders, WeatherEdge.Trading.DutchOrder

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(station_code market_cluster_id target_date total_invested guaranteed_payout guaranteed_profit_pct coverage num_outcomes)a
  @optional_fields ~w(status winning_outcome actual_pnl current_value sell_recommendation sell_reason closed_at)a

  def changeset(group, attrs) do
    group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:station_code)
    |> foreign_key_constraint(:market_cluster_id)
    |> unique_constraint([:station_code, :market_cluster_id])
  end
end
