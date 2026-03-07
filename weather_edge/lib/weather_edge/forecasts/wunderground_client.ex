defmodule WeatherEdge.Forecasts.WundergroundClient do
  @moduledoc """
  Fetches historical actual temperatures from Weather Underground history pages.
  """

  require Logger

  @doc """
  Fetches the actual max temperature for a station on a given date.
  Uses the Weather Underground history page HTML and extracts the max temp.

  Returns `{:ok, max_temp_celsius}` or `{:error, reason}`.
  """
  def get_actual_max_temp(station_code, %Date{} = date) do
    url = history_url(station_code, date)

    case Req.get(url, receive_timeout: 15_000, retry: :transient, max_retries: 2) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_max_temp(body)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches the Weather Underground forecast max temperature for a station on a given date.
  Scrapes the forecast page for the predicted high.

  Returns `{:ok, max_temp_celsius}` or `{:error, reason}`.
  """
  def get_forecast_max_temp(station_code, %Date{} = date, opts \\ []) do
    url = forecast_url(station_code, opts)

    case Req.get(url,
           receive_timeout: 15_000,
           retry: :transient,
           max_retries: 1,
           headers: [{"user-agent", "Mozilla/5.0"}]
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_forecast_temp(body, date)

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("WU forecast HTTP #{status} for #{station_code} (url: #{url})")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp forecast_url(station_code, opts) do
    cond do
      # Use explicit WU URL if provided by the station record
      wu_url = Keyword.get(opts, :wunderground_url) ->
        wu_url

      # Use lat/lon for GPS-based forecast (works for all stations worldwide)
      lat = Keyword.get(opts, :latitude) ->
        lon = Keyword.get(opts, :longitude)
        "https://www.wunderground.com/forecast/#{lat},#{lon}"

      # Fallback to station code (only works for US stations)
      true ->
        "https://www.wunderground.com/forecast/#{station_code}"
    end
  end

  defp parse_forecast_temp(html, target_date) when is_binary(html) do
    # WU embeds forecast JSON with daily highs in the page
    # Look for the target date's high temperature
    date_str = Calendar.strftime(target_date, "%-m/%-d")

    cond do
      # Try embedded JSON forecast data with "high" temperature
      match = Regex.run(~r/"#{Regex.escape(date_str)}"[^}]*?"high":\s*(\d+)/s, html) ->
        {temp_f, _} = Integer.parse(Enum.at(match, 1))
        {:ok, round((temp_f - 32) * 5 / 9)}

      # Try looking for temperature values near the target date string
      match = Regex.run(~r/#{Regex.escape(date_str)}[^0-9]*?(\d{2,3})\s*°/s, html) ->
        {temp_f, _} = Integer.parse(Enum.at(match, 1))
        {:ok, round((temp_f - 32) * 5 / 9)}

      true ->
        {:error, :forecast_not_found}
    end
  end

  defp history_url(station_code, date) do
    formatted = Calendar.strftime(date, "%Y-%m-%d")

    "https://www.wunderground.com/history/daily/#{station_code}/date/#{formatted}"
  end

  defp parse_max_temp(html) when is_binary(html) do
    # Weather Underground embeds history data in JSON-LD or in the page body.
    # Look for the max temperature in the history observation summary.
    # The page contains a table with "Max Temperature" row showing the value in F.
    # We also try the JSON data embedded in the page.
    with {:ok, temp_f} <- extract_max_temp_from_html(html) do
      temp_c = round((temp_f - 32) * 5 / 9)
      {:ok, temp_c}
    end
  end

  defp extract_max_temp_from_html(html) do
    # Strategy 1: Look for the lib-city-history-summary JSON data
    # Weather Underground pages embed data in <script> tags with JSON
    cond do
      # Try extracting from the history summary table pattern
      # The page has "Max Temperature" followed by the actual value in °F
      match = Regex.run(~r/Max\s*Temperature[^0-9]*?(\d+)\s*°?\s*F/i, html) ->
        {temp_f, _} = Integer.parse(Enum.at(match, 1))
        {:ok, temp_f}

      # Try JSON embedded observation data (api.weather.com responses embedded in page)
      match =
          Regex.run(
            ~r/"tempHigh":\s*(\d+)/,
            html
          ) ->
        {temp_f, _} = Integer.parse(Enum.at(match, 1))
        {:ok, temp_f}

      # Try the imperial max temp from embedded JSON
      match = Regex.run(~r/"maxTempAvg":\s*(\d+)/, html) ->
        {temp_f, _} = Integer.parse(Enum.at(match, 1))
        {:ok, temp_f}

      true ->
        {:error, :temp_not_found}
    end
  end
end
