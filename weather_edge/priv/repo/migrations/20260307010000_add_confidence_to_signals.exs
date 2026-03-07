defmodule WeatherEdge.Repo.Migrations.AddConfidenceToSignals do
  use Ecto.Migration

  def change do
    alter table(:signals) do
      add :confidence, :string, size: 20
    end
  end
end
