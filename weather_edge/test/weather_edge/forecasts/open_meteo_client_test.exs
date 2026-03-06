defmodule WeatherEdge.Forecasts.OpenMeteoClientTest do
  use ExUnit.Case, async: true

  alias WeatherEdge.Forecasts.OpenMeteoClient

  @target_date ~D[2026-03-10]

  defp build_hourly_data(_model, temps) do
    times =
      Enum.with_index(temps)
      |> Enum.map(fn {_temp, idx} ->
        hour = rem(idx, 24)
        day_offset = div(idx, 24)
        date = Date.add(@target_date, day_offset)
        "#{Date.to_iso8601(date)}T#{String.pad_leading(Integer.to_string(hour), 2, "0")}:00"
      end)

    %{
      "time" => times,
      "temperature_2m" => temps
    }
  end

  defp build_api_response(model_data) do
    Enum.into(model_data, %{}, fn {model, temps} ->
      {"hourly_#{model}", build_hourly_data(model, temps)}
    end)
  end

  describe "extract_daily_max/2" do
    test "extracts daily maximum temperature from hourly data" do
      temps = [15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0,
               28.3, 27.0, 26.5, 25.0, 24.0, 23.0, 22.0, 21.0, 20.0, 19.0, 18.0, 17.0]

      response = build_api_response(%{"gfs" => temps, "ecmwf_ifs" => temps})

      result = OpenMeteoClient.extract_daily_max(response, @target_date)

      assert result["gfs"] == 28.3
      assert result["ecmwf_ifs"] == 28.3
    end

    test "handles partial model failures (missing models in response)" do
      temps = [15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0,
               27.5, 27.0, 26.5, 25.0, 24.0, 23.0, 22.0, 21.0, 20.0, 19.0, 18.0, 17.0]

      response = build_api_response(%{"gfs" => temps})

      result = OpenMeteoClient.extract_daily_max(response, @target_date)

      assert result["gfs"] == 27.5
      refute Map.has_key?(result, "ecmwf_ifs")
      refute Map.has_key?(result, "icon_global")
    end

    test "handles multi-day response filtering only target_date" do
      day1_temps = [15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0,
                    28.0, 27.0, 26.5, 25.0, 24.0, 23.0, 22.0, 21.0, 20.0, 19.0, 18.0, 17.0]
      day2_temps = [14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 35.0, 34.0, 33.0,
                    32.0, 31.0, 30.0, 29.0, 28.0, 27.0, 26.0, 25.0, 24.0, 23.0, 22.0, 21.0]

      all_temps = day1_temps ++ day2_temps

      times =
        Enum.with_index(all_temps)
        |> Enum.map(fn {_temp, idx} ->
          hour = rem(idx, 24)
          day_offset = div(idx, 24)
          date = Date.add(@target_date, day_offset)
          "#{Date.to_iso8601(date)}T#{String.pad_leading(Integer.to_string(hour), 2, "0")}:00"
        end)

      response = %{
        "hourly_gfs" => %{
          "time" => times,
          "temperature_2m" => all_temps
        }
      }

      result = OpenMeteoClient.extract_daily_max(response, @target_date)

      assert result["gfs"] == 28.0
    end

    test "returns empty map when no data for target date" do
      response = build_api_response(%{})
      result = OpenMeteoClient.extract_daily_max(response, @target_date)
      assert result == %{}
    end

    test "handles multiple models with different max temps" do
      gfs_temps = [15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0,
                   28.3, 27.0, 26.5, 25.0, 24.0, 23.0, 22.0, 21.0, 20.0, 19.0, 18.0, 17.0]
      jma_temps = [14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0,
                   27.8, 26.5, 25.0, 24.0, 23.0, 22.0, 21.0, 20.0, 19.0, 18.0, 17.0, 16.0]

      response = build_api_response(%{"gfs" => gfs_temps, "jma" => jma_temps})

      result = OpenMeteoClient.extract_daily_max(response, @target_date)

      assert result["gfs"] == 28.3
      assert result["jma"] == 27.8
    end
  end

  describe "fetch_all_models/3" do
    setup do
      bypass = Bypass.open()

      Application.put_env(:weather_edge, :forecasts,
        open_meteo_base_url: "http://localhost:#{bypass.port}/v1",
        models: ["gfs", "ecmwf_ifs", "icon_global", "jma", "gem_global"]
      )

      on_exit(fn ->
        Application.put_env(:weather_edge, :forecasts, [])
      end)

      {:ok, bypass: bypass}
    end

    test "returns API response body on success", %{bypass: bypass} do
      response_body = %{"hourly_gfs" => %{"time" => [], "temperature_2m" => []}}

      Bypass.expect_once(bypass, "GET", "/v1/forecast", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response_body))
      end)

      assert {:ok, ^response_body} = OpenMeteoClient.fetch_all_models(-23.5, -46.6, 7)
    end

    test "returns api_error on non-200 status", %{bypass: bypass} do
      # Use stub since Req retries on 500
      Bypass.stub(bypass, "GET", "/v1/forecast", fn conn ->
        Plug.Conn.resp(conn, 500, "Server Error")
      end)

      assert {:error, {:api_error, 500}} = OpenMeteoClient.fetch_all_models(-23.5, -46.6)
    end
  end
end
