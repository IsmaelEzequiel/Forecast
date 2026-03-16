defmodule WeatherEdge.Trading.DutchOrder do
  use Ecto.Schema
  import Ecto.Changeset

  schema "dutch_orders" do
    field :outcome_label, :string
    field :token_id_yes, :string
    field :buy_price, :float
    field :current_price, :float
    field :tokens, :float
    field :invested, :float
    field :current_value, :float
    field :polymarket_order_id, :string
    field :status, :string, default: "filled"

    belongs_to :dutch_group, WeatherEdge.Trading.DutchGroup
  end

  @required_fields ~w(dutch_group_id outcome_label token_id_yes buy_price tokens invested)a
  @optional_fields ~w(current_price current_value polymarket_order_id status)a

  def changeset(order, attrs) do
    order
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:dutch_group_id)
  end
end
