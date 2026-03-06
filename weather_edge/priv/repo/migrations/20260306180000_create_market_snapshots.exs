defmodule WeatherEdge.Repo.Migrations.CreateMarketSnapshots do
  use Ecto.Migration

  def up do
    create table(:market_snapshots, primary_key: false) do
      add :id, :bigserial, primary_key: false
      add :market_cluster_id, references(:market_clusters, type: :bigint), null: false
      add :snapshot_at, :timestamptz, null: false, primary_key: false
      add :outcome_label, :string, size: 30, null: false
      add :yes_price, :float
      add :no_price, :float
      add :volume, :float
    end

    execute "ALTER TABLE market_snapshots ADD PRIMARY KEY (id, snapshot_at)"
    execute "SELECT create_hypertable('market_snapshots', 'snapshot_at')"
  end

  def down do
    drop table(:market_snapshots)
  end
end
