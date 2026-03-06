defmodule WeatherEdge.Calibration.Accuracy do
  use Ecto.Schema
  import Ecto.Changeset

  schema "forecast_accuracy" do
    field :target_date, :date
    field :predicted_distribution, :map
    field :actual_temp, :integer
    field :model_errors, :map
    field :best_edge, :float
    field :auto_buy_outcome, :string
    field :auto_buy_pnl, :float
    field :resolution_correct, :boolean

    belongs_to :station, WeatherEdge.Stations.Station,
      foreign_key: :station_code,
      references: :code,
      type: :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields ~w(station_code target_date predicted_distribution actual_temp model_errors resolution_correct)a
  @optional_fields ~w(best_edge auto_buy_outcome auto_buy_pnl)a

  def changeset(accuracy, attrs) do
    accuracy
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:station_code, max: 4)
    |> validate_length(:auto_buy_outcome, max: 20)
    |> unique_constraint([:station_code, :target_date])
    |> foreign_key_constraint(:station_code)
  end
end
