defmodule WeatherEdge.Repo.Migrations.WidenOutcomeLabelColumns do
  use Ecto.Migration

  def change do
    alter table(:market_snapshots) do
      modify :outcome_label, :string, size: 255, null: false
    end

    alter table(:positions) do
      modify :outcome_label, :string, size: 255
    end

    alter table(:signals) do
      modify :outcome_label, :string, size: 255
    end
  end
end
