defmodule WeatherEdge.Repo.Migrations.AddTagSlugToStations do
  use Ecto.Migration

  def change do
    alter table(:stations) do
      add :tag_slug, :string
    end
  end
end
