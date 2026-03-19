# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :weather_edge,
  ecto_repos: [WeatherEdge.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :weather_edge, WeatherEdgeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WeatherEdgeWeb.ErrorHTML, json: WeatherEdgeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WeatherEdge.PubSub,
  live_view: [signing_salt: "0EcFaS6F"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  weather_edge: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  weather_edge: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban job processing
config :weather_edge, Oban,
  repo: WeatherEdge.Repo,
  queues: [scanner: 5, forecasts: 3, trading: 2, signals: 3, cleanup: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 3600 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 */2 * * *", WeatherEdge.Workers.EventScannerWorker, queue: :scanner},
       {"* */2 * * *", WeatherEdge.Workers.ForecastRefreshWorker, queue: :forecasts},
       {"* */1 * * *", WeatherEdge.Workers.PriceSnapshotWorker, queue: :signals},
       {"*/10 * * * *", WeatherEdge.Workers.PositionMonitorWorker, queue: :signals},
       {"0 6,12,23 * * *", WeatherEdge.Workers.ResolutionWorker, queue: :cleanup},
       {"* */1 * * *", WeatherEdge.Workers.DutchMonitorWorker, queue: :signals},
       {"0 6 * * *", WeatherEdge.Workers.DutchResolverWorker, queue: :cleanup},
       {"0 6 * * *", WeatherEdge.Workers.DataCleanupWorker, queue: :cleanup}
     ]}
  ]

# Trading safety config
config :weather_edge, :trading,
  min_reserve_usdc: 0.50,
  max_orders_per_minute: 6,
  max_position_per_event: 1,
  order_retry_delay_ms: 30_000

# Forecast config
config :weather_edge, :forecasts,
  models: ["gfs", "ecmwf_ifs", "icon_global", "jma", "gem_global", "ukmo", "arpege",
           "bom_access_global", "cma_grapes_global", "kma_gdps"],
  open_meteo_base_url: "https://api.open-meteo.com/v1",
  metar_base_url: "https://aviationweather.gov"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
