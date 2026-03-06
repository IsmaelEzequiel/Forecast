defmodule WeatherEdge.Trading.ClobClient do
  @moduledoc """
  HTTP client for Polymarket's CLOB API.
  Includes public endpoints (prices, orderbook) and authenticated endpoints
  (order placement, cancellation, open orders).
  """

  alias WeatherEdge.Trading.Auth

  @base_url "https://clob.polymarket.com"

  # Zero address used as taker for market orders
  @zero_address "0x0000000000000000000000000000000000000000"

  # Fee rate in basis points (default 0)
  @default_fee_rate_bps 0

  @spec get_price(String.t(), String.t()) :: {:ok, float()} | {:error, term()}
  def get_price(token_id, side) when is_binary(token_id) and side in ["buy", "sell"] do
    url = "#{base_url()}/price"

    case Req.get(url, params: [token_id: token_id, side: side], receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: %{"price" => price}}} when is_binary(price) ->
        {value, _} = Float.parse(price)
        {:ok, value}

      {:ok, %Req.Response{status: 200, body: %{"price" => price}}} when is_number(price) ->
        {:ok, price / 1}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:api_error, status}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get_orderbook(String.t()) :: {:ok, %{bids: list(map()), asks: list(map())}} | {:error, term()}
  def get_orderbook(token_id) when is_binary(token_id) do
    url = "#{base_url()}/book"

    case Req.get(url, params: [token_id: token_id], receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: %{"bids" => bids, "asks" => asks}}} ->
        {:ok, %{bids: parse_levels(bids), asks: parse_levels(asks)}}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:api_error, status}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get_market(String.t()) :: {:ok, map()} | {:error, term()}
  def get_market(condition_id) when is_binary(condition_id) do
    url = "#{base_url()}/markets/#{condition_id}"

    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:api_error, status}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Authenticated Endpoints ---

  @doc """
  Places an order on Polymarket CLOB with EIP-712 signed order and L2 auth headers.

  Parameters:
    - token_id: the CLOB token ID for the outcome
    - side: "BUY" or "SELL"
    - price: float price per share (0.0 to 1.0)
    - size: float number of shares
    - type: order type, defaults to "GTC" (Good Til Cancelled)

  Returns `{:ok, order_response}` or `{:error, reason}`.
  """
  @spec place_order(String.t(), String.t(), float(), float(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def place_order(token_id, side, price, size, type \\ "GTC")
      when is_binary(token_id) and side in ["BUY", "SELL"] do
    config = polymarket_config()
    wallet_address = config[:wallet_address]

    if is_nil(wallet_address) do
      {:error, :missing_wallet_address}
    else
      order_struct = build_order_struct(token_id, side, price, size, wallet_address)

      with {:ok, signature} <- Auth.sign_order(order_struct),
           {:ok, headers} <- Auth.sign_request("POST", "/order") do
        body =
          Jason.encode!(%{
            order: %{
              salt: order_struct[:salt],
              maker: order_struct[:maker],
              signer: order_struct[:signer],
              taker: order_struct[:taker],
              tokenId: to_string(order_struct[:token_id]),
              makerAmount: to_string(order_struct[:maker_amount]),
              takerAmount: to_string(order_struct[:taker_amount]),
              expiration: to_string(order_struct[:expiration]),
              nonce: to_string(order_struct[:nonce]),
              feeRateBps: to_string(order_struct[:fee_rate_bps]),
              side: side_to_int(side),
              signatureType: order_struct[:signature_type]
            },
            signature: signature,
            orderType: type
          })

        url = "#{base_url()}/order"

        case Req.post(url,
               body: body,
               headers: Map.merge(headers, %{"content-type" => "application/json"}),
               receive_timeout: 15_000
             ) do
          {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
            {:ok, body}

          {:ok, %Req.Response{status: status, body: body}} when status in [200, 201] ->
            {:ok, body}

          {:ok, %Req.Response{status: 429}} ->
            {:error, :rate_limited}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, %Req.TransportError{reason: :timeout}} ->
            {:error, :timeout}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Cancels an order by order ID with L2 auth headers.

  Returns `{:ok, response}` or `{:error, reason}`.
  """
  @spec cancel_order(String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_order(order_id) when is_binary(order_id) do
    path = "/order"
    body = Jason.encode!(%{orderID: order_id})

    with {:ok, headers} <- Auth.sign_request("DELETE", path, body) do
      url = "#{base_url()}#{path}"

      case Req.request(
             method: :delete,
             url: url,
             body: body,
             headers: Map.merge(headers, %{"content-type" => "application/json"}),
             receive_timeout: 15_000
           ) do
        {:ok, %Req.Response{status: status, body: body}} when status in [200, 204] ->
          {:ok, body}

        {:ok, %Req.Response{status: 429}} ->
          {:error, :rate_limited}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, %Req.TransportError{reason: :timeout}} ->
          {:error, :timeout}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets all open orders for the authenticated user with L2 auth headers.

  Returns `{:ok, [order]}` or `{:error, reason}`.
  """
  @spec get_open_orders() :: {:ok, list(map())} | {:error, term()}
  def get_open_orders do
    path = "/orders"

    with {:ok, headers} <- Auth.sign_request("GET", path) do
      url = "#{base_url()}#{path}"

      case Req.get(url, headers: headers, receive_timeout: 15_000) do
        {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
          {:ok, body}

        {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
          {:ok, Map.get(body, "orders", [body])}

        {:ok, %Req.Response{status: 429}} ->
          {:error, :rate_limited}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, %Req.TransportError{reason: :timeout}} ->
          {:error, :timeout}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # --- Order Building ---

  defp build_order_struct(token_id, side, price, size, wallet_address) do
    # Convert price/size to USDC amounts (6 decimals)
    # BUY: maker pays USDC (makerAmount = price * size * 1e6), receives shares (takerAmount = size * 1e6)
    # SELL: maker provides shares (makerAmount = size * 1e6), receives USDC (takerAmount = price * size * 1e6)
    usdc_amount = round(price * size * 1_000_000)
    share_amount = round(size * 1_000_000)

    {maker_amount, taker_amount} =
      case side do
        "BUY" -> {usdc_amount, share_amount}
        "SELL" -> {share_amount, usdc_amount}
      end

    # Parse token_id to integer for EIP-712 encoding
    token_id_int =
      case Integer.parse(token_id) do
        {n, ""} -> n
        _ -> 0
      end

    %{
      salt: :rand.uniform(1_000_000_000),
      maker: wallet_address,
      signer: wallet_address,
      taker: @zero_address,
      token_id: token_id_int,
      maker_amount: maker_amount,
      taker_amount: taker_amount,
      expiration: 0,
      nonce: 0,
      fee_rate_bps: @default_fee_rate_bps,
      side: side_to_int(side),
      signature_type: 0
    }
  end

  defp side_to_int("BUY"), do: 0
  defp side_to_int("SELL"), do: 1

  # --- Public Endpoint Helpers ---

  defp parse_levels(levels) when is_list(levels) do
    Enum.map(levels, fn level ->
      %{
        price: parse_number(level["price"]),
        size: parse_number(level["size"])
      }
    end)
  end

  defp parse_levels(_), do: []

  defp parse_number(value) when is_binary(value) do
    {num, _} = Float.parse(value)
    num
  end

  defp parse_number(value) when is_number(value), do: value / 1
  defp parse_number(_), do: 0.0

  defp base_url do
    Application.get_env(:weather_edge, :clob_api_url) || @base_url
  end

  defp polymarket_config do
    Application.get_env(:weather_edge, :polymarket, [])
  end
end
