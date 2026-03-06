defmodule WeatherEdge.Repo.Migrations.AddTempUnitToStations do
  use Ecto.Migration

  def change do
    alter table(:stations) do
      add :temp_unit, :string, default: "C", null: false
    end
  end
end
