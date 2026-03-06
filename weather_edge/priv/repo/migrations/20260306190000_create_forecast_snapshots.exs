defmodule WeatherEdge.Repo.Migrations.CreateForecastSnapshots do
  use Ecto.Migration

  def up do
    create table(:forecast_snapshots, primary_key: false) do
      add :id, :bigserial, primary_key: false
      add :station_code, references(:stations, column: :code, type: :string), null: false
      add :fetched_at, :timestamptz, null: false, primary_key: false
      add :target_date, :date, null: false
      add :model, :string, size: 20, null: false
      add :max_temp_c, :float, null: false
      add :hourly_temps, :jsonb
    end

    execute "ALTER TABLE forecast_snapshots ADD PRIMARY KEY (id, fetched_at)"
    execute "SELECT create_hypertable('forecast_snapshots', 'fetched_at')"
  end

  def down do
    drop table(:forecast_snapshots)
  end
end
