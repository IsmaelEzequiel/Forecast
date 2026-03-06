defmodule WeatherEdge.Repo.Migrations.CreateStations do
  use Ecto.Migration

  def change do
    create table(:stations) do
      add :code, :string, size: 4, null: false
      add :city, :string, size: 100, null: false
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :country, :string, size: 2, null: false
      add :wunderground_url, :text
      add :monitoring_enabled, :boolean, default: true
      add :auto_buy_enabled, :boolean, default: false
      add :max_buy_price, :float, default: 0.20
      add :buy_amount_usdc, :float, default: 5.00
      add :slug_pattern, :string, size: 200

      timestamps(type: :timestamptz)
    end

    create unique_index(:stations, [:code])
  end
end
