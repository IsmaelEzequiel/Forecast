defmodule WeatherEdgeWeb.Router do
  use WeatherEdgeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WeatherEdgeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WeatherEdgeWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", WeatherEdgeWeb do
    pipe_through [:browser, WeatherEdgeWeb.Plugs.RequireAuth]

    live_session :authenticated, on_mount: WeatherEdgeWeb.Live.AuthHook do
      live "/", DashboardLive
      live "/stations/:code/events/:event_id", StationDetailLive
      live "/docs", DocsLive
      live "/analytics", AnalyticsLive
    end
  end

  scope "/api", WeatherEdgeWeb do
    pipe_through :api

    post "/sidecar/sync", SidecarController, :sync
  end

  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through [:browser, WeatherEdgeWeb.Plugs.RequireAuth]

    live_dashboard "/dashboard",
      metrics: WeatherEdgeWeb.Telemetry,
      additional_pages: [
        oban: Oban.LiveDashboard
      ]
  end
end
