defmodule WeatherEdge.Forecasts.MetarClient do
  @moduledoc """
  HTTP client for the Aviation Weather METAR API.
  Validates ICAO station codes and fetches current weather observations.
  """

  @base_url Application.compile_env(:weather_edge, :forecasts)[:metar_base_url] ||
              "https://aviationweather.gov"

  @doc """
  Validates an ICAO station code by fetching its METAR data.
  Returns station info on success.
  """
  @spec validate_station(String.t()) :: {:ok, map()} | {:error, atom()}
  def validate_station(code) when is_binary(code) do
    url = "#{base_url()}/api/data/metar"

    case Req.get(url, params: [ids: code, format: "json"], receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: [metar | _]}} ->
        {:ok, parse_station_info(metar)}

      {:ok, %Req.Response{status: 200, body: []}} ->
        {:error, :invalid_station}

      {:ok, %Req.Response{status: 200, body: ""}} ->
        {:error, :invalid_station}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:api_error, status}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches and parses current METAR observation for a station.
  Returns temperature, wind speed, wind direction, and humidity.
  """
  @spec get_current_conditions(String.t()) :: {:ok, map()} | {:error, atom()}
  def get_current_conditions(code) when is_binary(code) do
    url = "#{base_url()}/api/data/metar"

    case Req.get(url, params: [ids: code, format: "json"], receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: [metar | _]}} ->
        {:ok, parse_conditions(metar)}

      {:ok, %Req.Response{status: 200, body: []}} ->
        {:error, :invalid_station}

      {:ok, %Req.Response{status: 200, body: ""}} ->
        {:error, :invalid_station}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:api_error, status}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:weather_edge, :forecasts)[:metar_base_url] || @base_url
  end

  defp parse_station_info(metar) do
    %{
      code: metar["icaoId"],
      city: metar["name"],
      latitude: parse_float(metar["lat"]),
      longitude: parse_float(metar["lon"]),
      country: extract_country(metar)
    }
  end

  defp parse_conditions(metar) do
    %{
      temperature_c: parse_float(metar["temp"]),
      dewpoint_c: parse_float(metar["dewp"]),
      wind_speed_kt: parse_float(metar["wspd"]),
      wind_direction: parse_int(metar["wdir"]),
      humidity: calculate_humidity(metar["temp"], metar["dewp"]),
      raw_observation: metar["rawOb"],
      observed_at: metar["reportTime"]
    }
  end

  defp calculate_humidity(temp, dewp) when not is_nil(temp) and not is_nil(dewp) do
    t = parse_float(temp)
    d = parse_float(dewp)

    if t && d do
      # Magnus formula approximation for relative humidity
      round(100 * :math.exp(17.625 * d / (243.04 + d)) / :math.exp(17.625 * t / (243.04 + t)))
    end
  end

  defp calculate_humidity(_, _), do: nil

  defp extract_country(metar) do
    # The METAR API doesn't always include country directly;
    # fall back to nil if not present
    metar["country"] || metar["state"]
  end

  defp parse_float(nil), do: nil
  defp parse_float(val) when is_float(val), do: val
  defp parse_float(val) when is_integer(val), do: val / 1

  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> nil
    end
  end
end
