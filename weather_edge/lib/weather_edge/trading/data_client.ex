defmodule WeatherEdge.Trading.DataClient do
  @moduledoc """
  HTTP client for Polymarket's Data API.
  Fetches wallet positions, activity, and USDC balance.
  """

  @base_url "https://data-api.polymarket.com"

  @spec get_positions(keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_positions(opts \\ []) do
    address = opts[:wallet_address] || wallet_address()
    url = "#{base_url()}/positions"

    case Req.get(url, params: [user: address], receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, Map.get(body, "positions", [body])}

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

  @spec get_activity(keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_activity(opts \\ []) do
    address = opts[:wallet_address] || wallet_address()
    url = "#{base_url()}/activity"

    case Req.get(url, params: [user: address], receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, Map.get(body, "activity", [body])}

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

  @spec get_balance(keyword()) :: {:ok, float()} | {:error, term()}
  def get_balance(opts \\ []) do
    address = opts[:wallet_address] || wallet_address()
    url = "#{base_url()}/balance"

    case Req.get(url, params: [user: address], receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: %{"balance" => balance}}} when is_binary(balance) ->
        {value, _} = Float.parse(balance)
        {:ok, value}

      {:ok, %Req.Response{status: 200, body: %{"balance" => balance}}} when is_number(balance) ->
        {:ok, balance / 1}

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

  defp wallet_address do
    Application.get_env(:weather_edge, :polymarket)[:wallet_address]
  end

  defp base_url do
    Application.get_env(:weather_edge, :data_api_url) || @base_url
  end
end
