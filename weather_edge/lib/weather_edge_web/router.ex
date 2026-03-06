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
    end
  end

  scope "/api", WeatherEdgeWeb do
    pipe_through :api

    post "/sidecar/sync", SidecarController, :sync
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:weather_edge, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WeatherEdgeWeb.Telemetry
    end
  end
end
