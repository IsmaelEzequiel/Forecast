defmodule WeatherEdge.Stations do
  @moduledoc """
  Context for managing weather stations.
  """

  import Ecto.Query
  alias WeatherEdge.Repo
  alias WeatherEdge.Stations.Station
  alias WeatherEdge.Forecasts.MetarClient
  alias WeatherEdge.PubSubHelper

  def list_stations do
    Repo.all(from s in Station, order_by: s.code)
  end

  def get_station(id) do
    case Repo.get(Station, id) do
      nil -> {:error, :not_found}
      station -> {:ok, station}
    end
  end

  def get_by_code(code) do
    case Repo.get_by(Station, code: code) do
      nil -> {:error, :not_found}
      station -> {:ok, station}
    end
  end

  def create_station(%{"code" => code} = attrs) do
    temp_unit = attrs["temp_unit"] || "C"
    create_station_with_code(String.upcase(code), temp_unit)
  end

  def create_station(%{code: code} = attrs) do
    temp_unit = attrs[:temp_unit] || "C"
    create_station_with_code(String.upcase(code), temp_unit)
  end

  defp create_station_with_code(code, temp_unit) do
    case MetarClient.validate_station(code) do
      {:ok, info} ->
        attrs =
          info
          |> Map.put(:monitoring_enabled, true)
          |> Map.put(:auto_buy_enabled, false)
          |> Map.put(:max_buy_price, 0.20)
          |> Map.put(:buy_amount_usdc, 5.00)
          |> Map.put(:slug_pattern, generate_slug_pattern(info.city, info.code))
          |> Map.put(:tag_slug, generate_tag_slug(info.code, info.city))
          |> Map.put(:temp_unit, temp_unit)

        %Station{}
        |> Station.changeset(attrs)
        |> Repo.insert()
        |> tap_broadcast(:station_created)

      {:error, :invalid_station} ->
        {:error, :invalid_station}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_station(%Station{} = station, attrs) do
    station
    |> Station.changeset(attrs)
    |> Repo.update()
    |> tap_broadcast(:station_updated)
  end

  def delete_station(%Station{} = station) do
    import Ecto.Query

    Repo.transaction(fn ->
      # Delete dependent records in order
      cluster_ids =
        from(c in WeatherEdge.Markets.MarketCluster, where: c.station_code == ^station.code, select: c.id)
        |> Repo.all()

      if cluster_ids != [] do
        from(s in WeatherEdge.Markets.MarketSnapshot, where: s.market_cluster_id in ^cluster_ids) |> Repo.delete_all()
        from(s in WeatherEdge.Signals.Signal, where: s.market_cluster_id in ^cluster_ids) |> Repo.delete_all()
        from(p in WeatherEdge.Trading.Position, where: p.market_cluster_id in ^cluster_ids) |> Repo.delete_all()
      end

      from(o in WeatherEdge.Trading.Order, where: o.station_code == ^station.code) |> Repo.delete_all()
      from(a in WeatherEdge.Calibration.Accuracy, where: a.station_code == ^station.code) |> Repo.delete_all()
      from(f in WeatherEdge.Forecasts.ForecastSnapshot, where: f.station_code == ^station.code) |> Repo.delete_all()
      from(c in WeatherEdge.Markets.MarketCluster, where: c.station_code == ^station.code) |> Repo.delete_all()

      case Repo.delete(station) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> tap_broadcast(:station_deleted)
  end

  defp generate_slug_pattern(nil, _code), do: nil

  defp generate_slug_pattern(city, code) do
    slug = city_to_slug(code, city)
    "highest-temperature-in-#{slug}-on-*"
  end

  # Well-known ICAO -> Polymarket slug mappings for cities whose
  # METAR names don't match the slug (e.g. "New York/La Guardia" -> "nyc")
  @icao_slug_overrides %{
    "KLGA" => "nyc",
    "KJFK" => "nyc",
    "KEWR" => "nyc",
    "CYYZ" => "toronto",
    "SBGR" => "sao-paulo",
    "SBSP" => "sao-paulo",
    "EGLL" => "london",
    "EGKK" => "london",
    "RJTT" => "tokyo",
    "RJAA" => "tokyo",
    "LFPG" => "paris",
    "LFPO" => "paris",
    "VHHH" => "hong-kong",
    "OMDB" => "dubai",
    "WSSS" => "singapore",
    "LEMD" => "madrid",
    "EDDF" => "frankfurt",
    "EHAM" => "amsterdam",
    "ZBAA" => "beijing",
    "ZSPD" => "shanghai",
    "VIDP" => "delhi",
    "VABB" => "mumbai",
    "YSSY" => "sydney",
    "YMML" => "melbourne",
    "FAOR" => "johannesburg",
    "SBGL" => "rio-de-janeiro",
    "SCEL" => "santiago",
    "SAEZ" => "buenos-aires",
    "MMMX" => "mexico-city",
    "RKSI" => "seoul",
    "LTFM" => "istanbul",
    "UUEE" => "moscow",
    "LIRF" => "rome",
    "LPPT" => "lisbon",
    "LSZH" => "zurich",
    "LOWW" => "vienna",
    "EKCH" => "copenhagen",
    "ENGM" => "oslo",
    "ESSA" => "stockholm",
    "EFHK" => "helsinki",
    "EPWA" => "warsaw",
    "LKPR" => "prague",
    "LHBP" => "budapest",
    "KORD" => "chicago",
    "KLAX" => "los-angeles",
    "KSFO" => "san-francisco",
    "KMIA" => "miami",
    "KIAH" => "houston",
    "KDFW" => "dallas",
    "KATL" => "atlanta",
    "KDEN" => "denver",
    "KBOS" => "boston",
    "KSEA" => "seattle",
    "KPHX" => "phoenix",
    "KDCA" => "washington-dc",
    "KIAD" => "washington-dc",
    "KMSP" => "minneapolis",
    "KDTW" => "detroit",
    "KCLE" => "cleveland",
    "KPHL" => "philadelphia",
    "KCVG" => "cincinnati",
    "KSTL" => "st-louis",
    "KMCI" => "kansas-city",
    "KPIT" => "pittsburgh",
    "KLAS" => "las-vegas",
    "KSAN" => "san-diego",
    "KPDX" => "portland",
    "CYVR" => "vancouver",
    "CYUL" => "montreal",
    "CYOW" => "ottawa",
    "CYWG" => "winnipeg",
    "CYEG" => "edmonton",
    "CYYC" => "calgary",
    "NZWN" => "wellington",
    "NZAA" => "auckland",
    "NZCH" => "christchurch",
    "EDDM" => "munich"
  }

  defp city_to_slug(code, city) do
    case Map.get(@icao_slug_overrides, String.upcase(code)) do
      nil -> extract_city_name(city)
      slug -> slug
    end
  end

  defp extract_city_name(city) do
    city
    # Take only the part before "/" or "," (e.g. "Toronto/Pearson Intl, ON, CA" -> "Toronto")
    |> String.split(~r{[/,]}, parts: 2)
    |> List.first()
    |> String.trim()
    # Strip common airport suffixes that don't appear in Polymarket slugs
    |> String.replace(~r/\s+(Intl|International|Airport|Arpt|Municipal|Regional|Metro|AFB)\b/i, "")
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  # Polymarket Gamma API tag_slug for city-based event search
  # These are the tag slugs used in the Gamma API, which differ from event slugs
  @icao_tag_slug_overrides %{
    "KLGA" => "new-york-city",
    "KJFK" => "new-york-city",
    "KEWR" => "new-york-city",
    "CYYZ" => "toronto",
    "SBGR" => "sao-paulo",
    "SBSP" => "sao-paulo",
    "EGLL" => "london",
    "EGKK" => "london",
    "RJTT" => "tokyo",
    "RJAA" => "tokyo",
    "LFPG" => "paris",
    "LFPO" => "paris",
    "VHHH" => "hong-kong",
    "OMDB" => "dubai",
    "WSSS" => "singapore",
    "LEMD" => "madrid",
    "EDDF" => "frankfurt",
    "EHAM" => "amsterdam",
    "VIDP" => "delhi",
    "VABB" => "mumbai",
    "YSSY" => "sydney",
    "YMML" => "melbourne",
    "FAOR" => "johannesburg",
    "SBGL" => "rio-de-janeiro",
    "SCEL" => "santiago",
    "SAEZ" => "buenos-aires",
    "MMMX" => "mexico-city",
    "RKSI" => "seoul",
    "KORD" => "chicago",
    "KLAX" => "los-angeles",
    "KSFO" => "san-francisco",
    "KMIA" => "miami",
    "KIAH" => "houston",
    "KDFW" => "dallas",
    "KATL" => "atlanta",
    "KDEN" => "denver",
    "KBOS" => "boston",
    "KSEA" => "seattle",
    "KPHX" => "phoenix",
    "KDCA" => "washington-dc",
    "KIAD" => "washington-dc",
    "KLAS" => "las-vegas",
    "KSAN" => "san-diego",
    "NZWN" => "wellington",
    "NZAA" => "auckland",
    "NZCH" => "christchurch",
    "EDDM" => "munich"
  }

  defp generate_tag_slug(code, city) do
    case Map.get(@icao_tag_slug_overrides, String.upcase(code)) do
      nil -> extract_city_name(city)
      tag -> tag
    end
  end

  defp tap_broadcast({:ok, station} = result, event) do
    PubSubHelper.broadcast(PubSubHelper.stations(), {event, station})
    result
  end

  defp tap_broadcast(error, _event), do: error
end
