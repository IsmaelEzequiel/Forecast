defmodule WeatherEdge.Trading.ClobClient do
  @moduledoc """
  HTTP client for Polymarket's CLOB API (read-only public endpoints).
  Fetches prices, orderbook data, and market info.
  """

  @base_url "https://clob.polymarket.com"

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
end
