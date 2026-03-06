defmodule WeatherEdge.Trading.SidecarClient do
  @moduledoc """
  HTTP client for the Node.js sidecar that handles Polymarket SDK operations.
  Drop-in replacement for ClobClient — route orders through the JS SDK.
  """

  @spec place_order(String.t(), String.t(), float(), float(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def place_order(token_id, side, price, size, _type \\ "FOK") when side in ["BUY", "SELL"] do
    post("/order", %{token_id: token_id, side: side, price: price, size: size})
  end

  @spec cancel_order(String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_order(order_id) do
    post("/cancel", %{order_id: order_id})
  end

  @spec get_open_orders() :: {:ok, list(map())} | {:error, term()}
  def get_open_orders do
    case get("/open-orders") do
      {:ok, orders} when is_list(orders) -> {:ok, orders}
      {:ok, body} -> {:ok, Map.get(body, "orders", [])}
      error -> error
    end
  end

  @spec get_price(String.t(), String.t()) :: {:ok, float()} | {:error, term()}
  def get_price(token_id, side) do
    # Delegate to ClobClient for public endpoints (no auth needed)
    WeatherEdge.Trading.ClobClient.get_price(token_id, side)
  end

  @spec get_orderbook(String.t()) :: {:ok, map()} | {:error, term()}
  def get_orderbook(token_id) do
    WeatherEdge.Trading.ClobClient.get_orderbook(token_id)
  end

  @spec get_market(String.t()) :: {:ok, map()} | {:error, term()}
  def get_market(condition_id) do
    WeatherEdge.Trading.ClobClient.get_market(condition_id)
  end

  @spec health() :: {:ok, map()} | {:error, term()}
  def health do
    get("/health")
  end

  defp post(path, payload) do
    url = "#{base_url()}#{path}"

    case Req.post(url,
           json: payload,
           headers: auth_headers(),
           receive_timeout: 30_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "result" => result}}} ->
        {:ok, result}

      {:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: %{"error" => error}}} ->
        {:error, {:sidecar_error, status, error}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:sidecar_error, status, body}}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, :sidecar_offline}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get(path) do
    url = "#{base_url()}#{path}"

    case Req.get(url, headers: auth_headers(), receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "result" => result}}} ->
        {:ok, result}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: %{"error" => error}}} ->
        {:error, {:sidecar_error, status, error}}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, :sidecar_offline}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:weather_edge, :sidecar_url, "http://localhost:4001")
  end

  defp auth_headers do
    secret = Application.get_env(:weather_edge, :sidecar_secret, "sidecar-dev-secret")
    %{"authorization" => "Bearer #{secret}"}
  end
end
