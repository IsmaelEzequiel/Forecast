defmodule WeatherEdgeWeb.SessionController do
  use WeatherEdgeWeb, :controller

  def new(conn, _params) do
    render(conn, :new, error: nil, layout: {WeatherEdgeWeb.Layouts, :root})
  end

  def create(conn, %{"username" => username, "password" => password}) do
    auth = Application.get_env(:weather_edge, :auth)

    if Plug.Crypto.secure_compare(username, auth[:username]) &&
         Plug.Crypto.secure_compare(password, auth[:password]) do
      conn
      |> put_session(:authenticated, true)
      |> redirect(to: "/")
    else
      render(conn, :new, error: "Invalid username or password", layout: {WeatherEdgeWeb.Layouts, :root})
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/login")
  end
end
