defmodule WeatherEdge.Signals.DetectorTest do
  use ExUnit.Case, async: true

  alias WeatherEdge.Signals.Detector
  alias WeatherEdge.Markets.MarketCluster
  alias WeatherEdge.Probability.Distribution

  defp make_cluster(outcomes) do
    %MarketCluster{
      id: 1,
      event_id: "evt_1",
      event_slug: "test-event",
      target_date: ~D[2026-03-10],
      outcomes: outcomes,
      resolved: false
    }
  end

  defp make_dist(probs), do: %Distribution{probabilities: probs}

  describe "detect_mispricings/2 edge calculation" do
    test "model_prob 0.50 vs market_price 0.30 = edge 0.20" do
      cluster = make_cluster([
        %{"outcome_label" => "28C", "yes_price" => 0.30, "no_price" => 0.70, "liquidity" => 100.0, "clob_token_ids" => ["tok1"]}
      ])

      dist = make_dist(%{"28C" => 0.50})

      {:ok, signals, _flags} = Detector.detect_mispricings(cluster, dist)

      assert [signal] = signals
      assert signal.outcome_label == "28C"
      assert_in_delta signal.edge, 0.20, 0.001
      assert signal.recommended_side == "YES"
      assert signal.model_probability == 0.50
    end

    test "NO side edge when model prob is low" do
      cluster = make_cluster([
        %{"outcome_label" => "28C", "yes_price" => 0.80, "no_price" => 0.20, "liquidity" => 100.0, "clob_token_ids" => ["tok1"]}
      ])

      # model says only 30% chance, but market charges 80% -> NO side has edge
      dist = make_dist(%{"28C" => 0.30})

      {:ok, signals, _flags} = Detector.detect_mispricings(cluster, dist)

      assert [signal] = signals
      # edge_no = (1.0 - 0.30) - 0.20 = 0.50
      assert_in_delta signal.edge, 0.50, 0.001
      assert signal.recommended_side == "NO"
    end
  end

  describe "alert level classification" do
    test "edge 0.08 with sufficient liquidity -> opportunity" do
      cluster = make_cluster([
        %{"outcome_label" => "28C", "yes_price" => 0.42, "no_price" => 0.58, "liquidity" => 50.0, "clob_token_ids" => ["tok1"]}
      ])

      dist = make_dist(%{"28C" => 0.50})

      {:ok, [signal], _flags} = Detector.detect_mispricings(cluster, dist)

      assert signal.alert_level == "opportunity"
      assert_in_delta signal.edge, 0.08, 0.001
    end

    test "edge 0.15 with sufficient liquidity -> strong" do
      cluster = make_cluster([
        %{"outcome_label" => "28C", "yes_price" => 0.35, "no_price" => 0.65, "liquidity" => 50.0, "clob_token_ids" => ["tok1"]}
      ])

      dist = make_dist(%{"28C" => 0.50})

      {:ok, [signal], _flags} = Detector.detect_mispricings(cluster, dist)

      assert signal.alert_level == "strong"
      assert_in_delta signal.edge, 0.15, 0.001
    end

    test "edge 0.25 -> extreme" do
      cluster = make_cluster([
        %{"outcome_label" => "28C", "yes_price" => 0.25, "no_price" => 0.75, "liquidity" => 5.0, "clob_token_ids" => ["tok1"]}
      ])

      dist = make_dist(%{"28C" => 0.50})

      {:ok, [signal], _flags} = Detector.detect_mispricings(cluster, dist)

      assert signal.alert_level == "extreme"
      assert_in_delta signal.edge, 0.25, 0.001
    end

    test "small edge with low liquidity -> no alert" do
      cluster = make_cluster([
        %{"outcome_label" => "28C", "yes_price" => 0.42, "no_price" => 0.58, "liquidity" => 10.0, "clob_token_ids" => ["tok1"]}
      ])

      dist = make_dist(%{"28C" => 0.50})

      {:ok, signals, _flags} = Detector.detect_mispricings(cluster, dist)

      # edge=0.08 but liquidity < 20 -> no alert
      assert signals == []
    end
  end

  describe "safe NO detection" do
    test "prob < 0.05 and no_price <= 0.92 -> safe_no" do
      cluster = make_cluster([
        %{"outcome_label" => "35C", "yes_price" => 0.10, "no_price" => 0.90, "liquidity" => 50.0, "clob_token_ids" => ["tok1"]}
      ])

      dist = make_dist(%{"28C" => 0.90, "35C" => 0.03})

      {:ok, [signal], _flags} = Detector.detect_mispricings(cluster, dist)

      assert signal.alert_level == "safe_no"
      assert signal.outcome_label == "35C"
    end

    test "prob < 0.05 but no_price > 0.92 -> no safe_no" do
      cluster = make_cluster([
        %{"outcome_label" => "35C", "yes_price" => 0.05, "no_price" => 0.95, "liquidity" => 50.0, "clob_token_ids" => ["tok1"]}
      ])

      dist = make_dist(%{"28C" => 0.90, "35C" => 0.03})

      {:ok, signals, _flags} = Detector.detect_mispricings(cluster, dist)

      # no_price 0.95 > 0.92, so no safe_no. And edge_no = 0.97 - 0.95 = 0.02, not enough for other alerts
      assert signals == []
    end
  end

  describe "structural mispricing" do
    test "sum of YES prices = 1.08 -> flagged" do
      cluster = make_cluster([
        %{"outcome_label" => "27C", "yes_price" => 0.36, "no_price" => 0.64, "liquidity" => 50.0, "clob_token_ids" => ["tok1"]},
        %{"outcome_label" => "28C", "yes_price" => 0.36, "no_price" => 0.64, "liquidity" => 50.0, "clob_token_ids" => ["tok2"]},
        %{"outcome_label" => "29C", "yes_price" => 0.36, "no_price" => 0.64, "liquidity" => 50.0, "clob_token_ids" => ["tok3"]}
      ])

      dist = make_dist(%{"27C" => 0.33, "28C" => 0.34, "29C" => 0.33})

      {:ok, _signals, flags} = Detector.detect_mispricings(cluster, dist)

      assert :structural_mispricing in flags
    end

    test "sum of YES prices = 1.00 -> not flagged" do
      cluster = make_cluster([
        %{"outcome_label" => "27C", "yes_price" => 0.33, "no_price" => 0.67, "liquidity" => 50.0, "clob_token_ids" => ["tok1"]},
        %{"outcome_label" => "28C", "yes_price" => 0.34, "no_price" => 0.66, "liquidity" => 50.0, "clob_token_ids" => ["tok2"]},
        %{"outcome_label" => "29C", "yes_price" => 0.33, "no_price" => 0.67, "liquidity" => 50.0, "clob_token_ids" => ["tok3"]}
      ])

      dist = make_dist(%{"27C" => 0.33, "28C" => 0.34, "29C" => 0.33})

      {:ok, _signals, flags} = Detector.detect_mispricings(cluster, dist)

      assert flags == []
    end
  end
end
