defmodule WeatherEdge.Trading.Position do
  use Ecto.Schema
  import Ecto.Changeset

  schema "positions" do
    field :outcome_label, :string
    field :side, :string
    field :token_id, :string
    field :tokens, :float
    field :avg_buy_price, :float
    field :total_cost_usdc, :float
    field :current_price, :float
    field :unrealized_pnl, :float
    field :status, :string, default: "open"
    field :recommendation, :string
    field :auto_bought, :boolean, default: false
    field :opened_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :close_price, :float
    field :realized_pnl, :float

    belongs_to :station, WeatherEdge.Stations.Station,
      foreign_key: :station_code,
      references: :code,
      type: :string

    belongs_to :market_cluster, WeatherEdge.Markets.MarketCluster

    has_many :orders, WeatherEdge.Trading.Order

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(station_code market_cluster_id outcome_label side token_id tokens avg_buy_price total_cost_usdc)a
  @optional_fields ~w(current_price unrealized_pnl status recommendation auto_bought opened_at closed_at close_price realized_pnl)a

  def changeset(position, attrs) do
    position
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:station_code)
    |> foreign_key_constraint(:market_cluster_id)
  end
end
