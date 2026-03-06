defmodule WeatherEdge.Markets.GammaClient do
  @moduledoc """
  HTTP client for Polymarket's Gamma API.
  Discovers temperature events and fetches event details.
  """

  @base_url "https://gamma-api.polymarket.com"

  @doc """
  Fetches events from the Gamma API with optional query parameters.

  ## Options
    * `:active` - filter by active status (boolean)
    * `:closed` - filter by closed status (boolean)
    * `:limit` - max number of events to return
    * `:offset` - pagination offset
    * `:order` - sort order (e.g., "startDate")
    * `:ascending` - sort direction (boolean)
    * `:tag` - filter by tag
  """
  @spec get_events(keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_events(params \\ []) do
    url = "#{base_url()}/events"

    case Req.get(url, params: params, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, List.wrap(body)}

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

  @doc """
  Searches events by query string.
  """
  @spec search_events(String.t()) :: {:ok, list(map())} | {:error, term()}
  def search_events(query) when is_binary(query) do
    get_events(tag: query)
  end

  @doc """
  Fetches a specific event by its slug.
  """
  @spec get_event_by_slug(String.t()) :: {:ok, map()} | {:error, term()}
  def get_event_by_slug(slug) when is_binary(slug) do
    url = "#{base_url()}/events"

    case Req.get(url, params: [slug: slug], receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: [event | _]}} ->
        {:ok, event}

      {:ok, %Req.Response{status: 200, body: []}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

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

  defp base_url do
    Application.get_env(:weather_edge, :gamma_api_url) || @base_url
  end
end
