defmodule WeatherEdgeWeb.Live.AuthHook do
  import Phoenix.LiveView

  def on_mount(:default, _params, session, socket) do
    if session["authenticated"] do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end
end
