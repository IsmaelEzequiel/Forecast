defmodule WeatherEdge.Repo.Migrations.CreateMarketClusters do
  use Ecto.Migration

  def change do
    create table(:market_clusters) do
      add :event_id, :string, size: 100, null: false
      add :event_slug, :string, size: 200, null: false
      add :station_code, references(:stations, column: :code, type: :string), size: 4
      add :target_date, :date, null: false
      add :title, :string, size: 300
      add :outcomes, :jsonb, null: false
      add :resolved, :boolean, default: false
      add :resolution_temp, :integer

      timestamps(type: :timestamptz)
    end

    create unique_index(:market_clusters, [:event_id])
    create index(:market_clusters, [:station_code, :target_date])
    create index(:market_clusters, [:resolved], where: "resolved = false", name: :market_clusters_unresolved_index)
  end
end
