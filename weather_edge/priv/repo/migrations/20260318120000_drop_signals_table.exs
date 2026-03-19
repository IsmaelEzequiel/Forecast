defmodule WeatherEdge.Repo.Migrations.DropSignalsTable do
  use Ecto.Migration

  def up do
    drop_if_exists table(:signals)
  end

  def down do
    :ok
  end
end
