defmodule WeatherEdgeWeb.DashboardLiveTest do
  use WeatherEdgeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias WeatherEdge.Repo
  alias WeatherEdge.Stations.Station
  alias WeatherEdge.PubSubHelper

  defp create_station(attrs \\ %{}) do
    defaults = %{
      code: "SBSP",
      city: "Sao Paulo",
      latitude: -23.627,
      longitude: -46.656,
      country: "BR",
      monitoring_enabled: true,
      auto_buy_enabled: false,
      max_buy_price: 0.20,
      buy_amount_usdc: 5.00,
      slug_pattern: "highest-temperature-in-sao-paulo-on-*"
    }

    %Station{}
    |> Station.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "dashboard renders" do
    test "renders empty state when no stations exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "No stations yet"
      assert html =~ "WEATHER EDGE"
    end

    test "renders station cards when stations exist", %{conn: conn} do
      create_station()

      {:ok, _view, html} = live(conn, "/")

      assert html =~ "SBSP"
      assert html =~ "Sao Paulo"
    end

    test "renders multiple station cards", %{conn: conn} do
      create_station(%{code: "SBSP", city: "Sao Paulo"})
      create_station(%{code: "KJFK", city: "New York", latitude: 40.639, longitude: -73.762, country: "US"})

      {:ok, _view, html} = live(conn, "/")

      assert html =~ "SBSP"
      assert html =~ "KJFK"
    end
  end

  describe "PubSub updates" do
    test "handles balance_updated broadcast", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      PubSubHelper.broadcast(PubSubHelper.portfolio_balance_update(), {:balance_updated, 47.23})

      html = render(view)
      assert html =~ "47.23"
    end

    test "handles station_created broadcast", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      assert html =~ "No stations yet"

      station = create_station()
      PubSubHelper.broadcast(PubSubHelper.stations(), {:station_created, station})

      html = render(view)
      assert html =~ "SBSP"
      assert html =~ "Sao Paulo"
    end

    test "handles signal_detected broadcast", %{conn: conn} do
      station = create_station()
      {:ok, view, _html} = live(conn, "/")

      signal = %{
        station_code: "SBSP",
        outcome_label: "28C",
        market_price: 0.30,
        edge: 0.15,
        alert_level: "strong",
        computed_at: DateTime.utc_now()
      }

      PubSubHelper.broadcast(PubSubHelper.station_signal(station.code), {:signal_detected, signal})

      html = render(view)
      assert html =~ "28C"
    end
  end

  describe "add station modal" do
    test "opens add station modal on button click", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html = view |> element("button", "+ Add Station") |> render_click()

      assert html =~ "Add Weather Station"
      assert html =~ "ICAO"
    end

    test "closes modal via event", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open modal
      view |> element("button", "+ Add Station") |> render_click()

      # Close via direct event push
      html = render_hook(view, "close_add_station_modal", %{})

      # Modal flag should be set to false
      refute html =~ "Add Weather Station"
    end
  end
end
