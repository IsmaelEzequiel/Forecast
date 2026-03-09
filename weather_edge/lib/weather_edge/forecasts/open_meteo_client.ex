defmodule WeatherEdge.Forecasts.OpenMeteoClient do
  @moduledoc """
  HTTP client for the Open-Meteo API.
  Fetches hourly temperature forecasts from multiple weather models.
  """

  @models ["gfs", "ecmwf_ifs", "icon_global", "jma", "gem_global", "ukmo", "arpege",
           "bom_access_global", "cma_grapes_global", "kma_gdps"]

  require Logger

  @spec fetch_all_models(float(), float(), pos_integer()) ::
          {:ok, map()} | {:error, term()}
  def fetch_all_models(latitude, longitude, forecast_days \\ 7) do
    results =
      models()
      |> Task.async_stream(
        fn model -> {model, fetch_single_model(latitude, longitude, model, forecast_days)} end,
        timeout: 30_000,
        max_concurrency: 4
      )
      |> Enum.reduce(%{}, fn
        {:ok, {model, {:ok, body}}}, acc ->
          Map.put(acc, "hourly_#{model}", Map.get(body, "hourly", %{}))

        {:ok, {model, {:error, reason}}}, acc ->
          Logger.warning("OpenMeteo: Model #{model} failed: #{inspect(reason)}")
          acc

        {:exit, reason}, acc ->
          Logger.warning("OpenMeteo: Task exited: #{inspect(reason)}")
          acc
      end)

    if results == %{} do
      {:error, :all_models_failed}
    else
      {:ok, results}
    end
  end

  defp fetch_single_model(latitude, longitude, model, forecast_days) do
    # Open-Meteo uses different base paths for some models
    {url, params} = model_url_and_params(model, latitude, longitude, forecast_days)

    case Req.get(url, params: params, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp model_url_and_params(model, lat, lon, days) do
    base = base_url()

    {endpoint, extra} =
      case model do
        "ecmwf_ifs" -> {"/ecmwf", []}
        "icon_global" -> {"/dwd-icon", []}
        "jma" -> {"/jma", []}
        "gem_global" -> {"/gem", []}
        "ukmo" -> {"/ukmo", []}
        "arpege" -> {"/meteofrance", []}
        "bom_access_global" -> {"/bom", []}
        "cma_grapes_global" -> {"/cma", []}
        "kma_gdps" -> {"/forecast", [models: "kma_gdps"]}
        _ -> {"/forecast", []}
      end

    params =
      [latitude: lat, longitude: lon, hourly: "temperature_2m", forecast_days: days, timezone: "UTC"] ++ extra

    {"#{base}#{endpoint}", params}
  end

  @spec extract_daily_max(map(), Date.t()) :: %{String.t() => float()}
  def extract_daily_max(api_response, target_date) do
    date_str = Date.to_iso8601(target_date)

    models()
    |> Enum.reduce(%{}, fn model, acc ->
      case extract_model_max(api_response, model, date_str) do
        {:ok, max_temp} -> Map.put(acc, model, max_temp)
        :error -> acc
      end
    end)
  end

  defp extract_model_max(response, model, date_str) do
    hourly_key = "hourly_#{model}" |> maybe_rename_key()

    with %{"time" => times, "temperature_2m" => temps} <- Map.get(response, hourly_key),
         indices <- date_indices(times, date_str),
         true <- indices != [] do
      max_temp =
        indices
        |> Enum.map(&Enum.at(temps, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.max(fn -> nil end)

      if max_temp, do: {:ok, max_temp / 1}, else: :error
    else
      _ -> :error
    end
  end

  defp date_indices(times, date_str) do
    times
    |> Enum.with_index()
    |> Enum.filter(fn {time, _idx} -> String.starts_with?(time, date_str) end)
    |> Enum.map(fn {_time, idx} -> idx end)
  end

  # Open-Meteo uses different key naming for some models
  defp maybe_rename_key("hourly_ecmwf_ifs"), do: "hourly_ecmwf_ifs"
  defp maybe_rename_key("hourly_icon_global"), do: "hourly_icon_global"
  defp maybe_rename_key("hourly_gem_global"), do: "hourly_gem_global"
  defp maybe_rename_key(key), do: key

  defp base_url do
    Application.get_env(:weather_edge, :forecasts)[:open_meteo_base_url] ||
      "https://api.open-meteo.com/v1"
  end

  defp models do
    Application.get_env(:weather_edge, :forecasts)[:models] || @models
  end
end
