defmodule WeatherEdge.Trading.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    field :station_code, :string
    field :order_id, :string
    field :token_id, :string
    field :side, :string
    field :price, :float
    field :size, :float
    field :usdc_amount, :float
    field :status, :string, default: "pending"
    field :auto_order, :boolean, default: false
    field :error_message, :string
    field :placed_at, :utc_datetime
    field :filled_at, :utc_datetime

    belongs_to :position, WeatherEdge.Trading.Position

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(station_code token_id side price size usdc_amount)a
  @optional_fields ~w(position_id order_id status auto_order error_message placed_at filled_at)a

  def changeset(order, attrs) do
    order
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:position_id)
  end
end
