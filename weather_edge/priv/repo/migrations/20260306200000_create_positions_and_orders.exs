defmodule WeatherEdge.Repo.Migrations.CreatePositionsAndOrders do
  use Ecto.Migration

  def change do
    create table(:positions) do
      add :station_code, references(:stations, column: :code, type: :varchar), null: false
      add :market_cluster_id, references(:market_clusters), null: false
      add :outcome_label, :varchar, size: 30, null: false
      add :side, :varchar, size: 3, null: false
      add :token_id, :text, null: false
      add :tokens, :float, null: false
      add :avg_buy_price, :float, null: false
      add :total_cost_usdc, :float, null: false
      add :current_price, :float
      add :unrealized_pnl, :float
      add :status, :varchar, size: 20, default: "open"
      add :recommendation, :varchar, size: 50
      add :auto_bought, :boolean, default: false
      add :opened_at, :timestamptz
      add :closed_at, :timestamptz
      add :close_price, :float
      add :realized_pnl, :float

      timestamps(type: :timestamptz)
    end

    create index(:positions, [:station_code], name: :idx_positions_station)
    create index(:positions, [:status], where: "status = 'open'", name: :idx_positions_open)

    create table(:orders) do
      add :position_id, references(:positions)
      add :station_code, :varchar, size: 4, null: false
      add :order_id, :varchar, size: 100
      add :token_id, :text, null: false
      add :side, :varchar, size: 4, null: false
      add :price, :float, null: false
      add :size, :float, null: false
      add :usdc_amount, :float, null: false
      add :status, :varchar, size: 20, default: "pending"
      add :auto_order, :boolean, default: false
      add :error_message, :text
      add :placed_at, :timestamptz
      add :filled_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create index(:orders, [:status], where: "status = 'pending'", name: :idx_orders_pending)
  end
end
