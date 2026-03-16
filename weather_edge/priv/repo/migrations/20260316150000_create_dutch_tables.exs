defmodule WeatherEdge.Repo.Migrations.CreateDutchTables do
  use Ecto.Migration

  def change do
    # Station dutching config fields
    alter table(:stations) do
      add :strategy, :string, default: "dutch"
      add :dutch_max_sum, :float, default: 0.85
      add :dutch_min_coverage, :float, default: 0.70
      add :dutch_max_outcomes, :integer, default: 5
      add :dutch_min_profit_pct, :float, default: 0.05
    end

    create table(:dutch_groups) do
      add :station_code, references(:stations, column: :code, type: :string), null: false
      add :market_cluster_id, references(:market_clusters), null: false
      add :target_date, :date, null: false
      add :total_invested, :float, null: false
      add :guaranteed_payout, :float, null: false
      add :guaranteed_profit_pct, :float, null: false
      add :coverage, :float, null: false
      add :num_outcomes, :integer, null: false
      add :status, :string, default: "open"
      add :winning_outcome, :string
      add :actual_pnl, :float
      add :current_value, :float
      add :sell_recommendation, :string
      add :sell_reason, :text
      add :closed_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: :updated_at)
    end

    create index(:dutch_groups, [:status], where: "status = 'open'", name: :idx_dutch_groups_open)
    create index(:dutch_groups, [:station_code])
    create unique_index(:dutch_groups, [:station_code, :market_cluster_id])

    create table(:dutch_orders) do
      add :dutch_group_id, references(:dutch_groups, on_delete: :delete_all), null: false
      add :outcome_label, :string, null: false
      add :token_id_yes, :text, null: false
      add :buy_price, :float, null: false
      add :current_price, :float
      add :tokens, :float, null: false
      add :invested, :float, null: false
      add :current_value, :float
      add :polymarket_order_id, :string
      add :status, :string, default: "filled"
    end

    create index(:dutch_orders, [:dutch_group_id])
  end
end
