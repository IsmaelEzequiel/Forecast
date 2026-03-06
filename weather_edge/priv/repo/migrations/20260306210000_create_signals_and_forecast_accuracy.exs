defmodule WeatherEdge.Repo.Migrations.CreateSignalsAndForecastAccuracy do
  use Ecto.Migration

  def up do
    create table(:signals, primary_key: false) do
      add :id, :bigserial, primary_key: false
      add :station_code, :string, size: 4, null: false
      add :market_cluster_id, references(:market_clusters, on_delete: :nothing), null: false
      add :computed_at, :timestamptz, null: false, primary_key: false
      add :outcome_label, :string, size: 30, null: false
      add :model_probability, :float, null: false
      add :market_price, :float, null: false
      add :edge, :float, null: false
      add :recommended_side, :string, size: 3, null: false
      add :alert_level, :string, size: 20
    end

    execute "ALTER TABLE signals ADD PRIMARY KEY (id, computed_at)"
    execute "SELECT create_hypertable('signals', 'computed_at')"

    create table(:forecast_accuracy) do
      add :station_code, references(:stations, column: :code, type: :string), null: false
      add :target_date, :date, null: false
      add :predicted_distribution, :jsonb, null: false
      add :actual_temp, :integer, null: false
      add :model_errors, :jsonb, null: false
      add :best_edge, :float
      add :auto_buy_outcome, :string, size: 20
      add :auto_buy_pnl, :float
      add :resolution_correct, :boolean, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end

    create unique_index(:forecast_accuracy, [:station_code, :target_date])
  end

  def down do
    drop table(:forecast_accuracy)
    drop table(:signals)
  end
end
