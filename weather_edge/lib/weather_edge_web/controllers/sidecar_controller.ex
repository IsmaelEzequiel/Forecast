defmodule WeatherEdgeWeb.SidecarController do
  use WeatherEdgeWeb, :controller

  alias WeatherEdge.PubSubHelper

  def sync(conn, %{"balance" => balance} = params) do
    secret = Application.get_env(:weather_edge, :sidecar_secret, "sidecar-dev-secret")

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(token, secret) do
      if is_number(balance) do
        :persistent_term.put(:sidecar_balance, balance)

        PubSubHelper.broadcast(
          PubSubHelper.portfolio_balance_update(),
          {:balance_updated, balance}
        )
      end

      if is_list(params["positions"]) do
        :persistent_term.put(:sidecar_positions, params["positions"])

        PubSubHelper.broadcast(
          PubSubHelper.portfolio_position_update(),
          {:positions_synced, params["positions"]}
        )
      end

      json(conn, %{ok: true})
    else
      _ -> conn |> put_status(401) |> json(%{error: "unauthorized"})
    end
  end
end
