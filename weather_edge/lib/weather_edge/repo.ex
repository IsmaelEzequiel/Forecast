defmodule WeatherEdge.Repo do
  use Ecto.Repo,
    otp_app: :weather_edge,
    adapter: Ecto.Adapters.Postgres
end
