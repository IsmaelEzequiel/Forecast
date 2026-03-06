defmodule WeatherEdge.Trading.OrderManagerTest do
  use WeatherEdge.DataCase, async: false

  alias WeatherEdge.Trading.OrderManager
  alias WeatherEdge.Trading.{Order, Position}
  alias WeatherEdge.Stations.Station
  alias WeatherEdge.Markets.MarketCluster

  setup do
    station =
      Repo.insert!(%Station{
        code: "KJFK",
        city: "New York",
        latitude: 40.6,
        longitude: -73.8,
        country: "US"
      })

    {:ok, cluster} =
      %MarketCluster{}
      |> MarketCluster.changeset(%{
        event_id: "evt_test_1",
        event_slug: "test-event",
        target_date: Date.add(Date.utc_today(), 2),
        station_code: station.code,
        outcomes: [
          %{
            "outcome_label" => "28C",
            "yes_price" => 0.50,
            "no_price" => 0.50,
            "clob_token_ids" => ["tok_28"]
          }
        ]
      })
      |> Repo.insert()

    outcome = %{
      "token_id" => "tok_28",
      "outcome_label" => "28C",
      "price" => 0.50,
      "market_cluster_id" => cluster.id,
      "event_id" => cluster.event_id
    }

    # Clean up persistent_term rate limits
    on_exit(fn ->
      try do
        :persistent_term.erase({:order_manager_rate_limit, "KJFK"})
      rescue
        ArgumentError -> :ok
      end
    end)

    %{station: station, cluster: cluster, outcome: outcome}
  end

  describe "balance check" do
    test "rejects when balance < amount + $2 reserve", %{outcome: outcome} do
      # Mock balance of $5.00, try to buy for $4.00 (needs $6.00 with $2 reserve)
      Process.put(:mock_balance, 5.0)

      result = OrderManager.place_buy_order("KJFK", outcome, 4.0)

      assert {:error, :insufficient_balance} = result
    end

    test "allows when balance >= amount + $2 reserve", %{outcome: outcome} do
      Process.put(:mock_balance, 10.0)

      result = OrderManager.place_buy_order("KJFK", outcome, 5.0)

      assert {:ok, %Order{}} = result
    end

    test "rejects at exact boundary (balance == amount + reserve - epsilon)", %{outcome: outcome} do
      # $2 reserve, buying $5 -> need >= $7. Balance is $6.99
      Process.put(:mock_balance, 6.99)

      result = OrderManager.place_buy_order("KJFK", outcome, 5.0)

      assert {:error, :insufficient_balance} = result
    end
  end

  describe "duplicate order prevention" do
    test "rejects duplicate order for same event + station", %{cluster: cluster, outcome: outcome} do
      Process.put(:mock_balance, 100.0)

      # Create existing position and order for this station + event
      {:ok, position} =
        %Position{}
        |> Position.changeset(%{
          station_code: "KJFK",
          market_cluster_id: cluster.id,
          outcome_label: "28C",
          side: "YES",
          token_id: "tok_28",
          tokens: 10.0,
          avg_buy_price: 0.50,
          total_cost_usdc: 5.0,
          status: "open"
        })
        |> Repo.insert()

      %Order{}
      |> Order.changeset(%{
        station_code: "KJFK",
        token_id: "tok_28",
        side: "BUY",
        price: 0.50,
        size: 10.0,
        usdc_amount: 5.0,
        status: "filled",
        position_id: position.id,
        placed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

      result = OrderManager.place_buy_order("KJFK", outcome, 5.0)

      assert {:error, :duplicate_order} = result
    end

    test "allows order for different event", %{outcome: outcome} do
      Process.put(:mock_balance, 100.0)

      # Create a cluster for a different event
      {:ok, different_cluster} =
        %MarketCluster{}
        |> MarketCluster.changeset(%{
          event_id: "evt_different",
          event_slug: "different-event",
          target_date: Date.add(Date.utc_today(), 3),
          station_code: "KJFK",
          outcomes: []
        })
        |> Repo.insert()

      {:ok, position} =
        %Position{}
        |> Position.changeset(%{
          station_code: "KJFK",
          market_cluster_id: different_cluster.id,
          outcome_label: "28C",
          side: "YES",
          token_id: "tok_other",
          tokens: 10.0,
          avg_buy_price: 0.50,
          total_cost_usdc: 5.0,
          status: "open"
        })
        |> Repo.insert()

      %Order{}
      |> Order.changeset(%{
        station_code: "KJFK",
        token_id: "tok_other",
        side: "BUY",
        price: 0.50,
        size: 10.0,
        usdc_amount: 5.0,
        status: "filled",
        position_id: position.id,
        placed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

      # This should succeed because the event_id is different
      result = OrderManager.place_buy_order("KJFK", outcome, 5.0)

      assert {:ok, %Order{}} = result
    end
  end

  describe "rate limiting" do
    test "second order within 10 seconds rejected", %{outcome: outcome} do
      Process.put(:mock_balance, 100.0)

      # Simulate a recent order by setting rate limit
      :persistent_term.put({:order_manager_rate_limit, "KJFK"}, System.monotonic_time(:second))

      result = OrderManager.place_buy_order("KJFK", outcome, 5.0)

      assert {:error, :rate_limited} = result
    end

    test "allows order after rate limit window expires", %{outcome: outcome} do
      Process.put(:mock_balance, 100.0)

      # Set rate limit 11 seconds ago
      :persistent_term.put(
        {:order_manager_rate_limit, "KJFK"},
        System.monotonic_time(:second) - 11
      )

      result = OrderManager.place_buy_order("KJFK", outcome, 5.0)

      assert {:ok, %Order{}} = result
    end
  end
end
