defmodule WeatherEdge.Markets.GammaClientTest do
  use ExUnit.Case, async: true

  alias WeatherEdge.Markets.GammaClient

  setup do
    bypass = Bypass.open()
    Application.put_env(:weather_edge, :gamma_api_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Application.delete_env(:weather_edge, :gamma_api_url)
    end)

    {:ok, bypass: bypass}
  end

  describe "get_events/1" do
    test "returns list of events on success", %{bypass: bypass} do
      events = [
        %{"id" => "evt1", "title" => "Temperature event", "slug" => "temp-event"},
        %{"id" => "evt2", "title" => "Another event", "slug" => "another-event"}
      ]

      Bypass.expect_once(bypass, "GET", "/events", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(events))
      end)

      assert {:ok, ^events} = GammaClient.get_events()
    end

    test "returns rate_limited error on 429", %{bypass: bypass} do
      # Use stub since Req may retry
      Bypass.stub(bypass, "GET", "/events", fn conn ->
        Plug.Conn.resp(conn, 429, "Too Many Requests")
      end)

      assert {:error, :rate_limited} = GammaClient.get_events()
    end

    test "returns api_error on non-200 status", %{bypass: bypass} do
      # Use stub since Req retries on 500
      Bypass.stub(bypass, "GET", "/events", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, {:api_error, 500}} = GammaClient.get_events()
    end
  end

  describe "get_event_by_slug/1" do
    test "returns event when found", %{bypass: bypass} do
      event = %{"id" => "evt1", "title" => "Temperature event", "slug" => "temp-event"}

      Bypass.expect_once(bypass, "GET", "/events", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!([event]))
      end)

      assert {:ok, ^event} = GammaClient.get_event_by_slug("temp-event")
    end

    test "returns not_found when empty result", %{bypass: bypass} do
      Bypass.expect_once(bypass, "GET", "/events", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!([]))
      end)

      assert {:error, :not_found} = GammaClient.get_event_by_slug("nonexistent")
    end
  end
end

defmodule WeatherEdge.Markets.EventParserTest do
  use ExUnit.Case, async: true

  alias WeatherEdge.Markets.EventParser

  @sample_event %{
    "id" => 12345,
    "slug" => "highest-temperature-in-new-york-on-march-10",
    "title" => "Highest temperature in New York on March 10",
    "markets" => [
      %{
        "question" => "Will the highest temperature be 27 degrees or below?",
        "outcomePrices" => ~s(["0.15", "0.85"]),
        "clobTokenIds" => "[tok_yes_27, tok_no_27]",
        "volume" => "1500.5",
        "liquidity" => "200.0"
      },
      %{
        "question" => "Will the highest temperature be 28 degrees?",
        "outcomePrices" => ~s(["0.35", "0.65"]),
        "clobTokenIds" => "[tok_yes_28, tok_no_28]",
        "volume" => "3200.0",
        "liquidity" => "500.0"
      },
      %{
        "question" => "Will the highest temperature be 29 degrees?",
        "outcomePrices" => ~s(["0.30", "0.70"]),
        "clobTokenIds" => "[tok_yes_29, tok_no_29]",
        "volume" => "2800.0",
        "liquidity" => "400.0"
      },
      %{
        "question" => "Will the highest temperature be 34 degrees or higher?",
        "outcomePrices" => ~s(["0.05", "0.95"]),
        "clobTokenIds" => "[tok_yes_34, tok_no_34]",
        "volume" => "100.0",
        "liquidity" => "50.0"
      }
    ]
  }

  describe "parse_event/1" do
    test "extracts event_id, slug, and title" do
      {:ok, attrs} = EventParser.parse_event(@sample_event)

      assert attrs.event_id == "12345"
      assert attrs.event_slug == "highest-temperature-in-new-york-on-march-10"
      assert attrs.title == "Highest temperature in New York on March 10"
    end

    test "extracts target_date from title" do
      {:ok, attrs} = EventParser.parse_event(@sample_event)

      assert attrs.target_date == ~D[2026-03-10]
    end

    test "extracts temperature outcomes with prices and token IDs" do
      {:ok, attrs} = EventParser.parse_event(@sample_event)

      assert length(attrs.outcomes) == 4

      [_outcome_27, outcome_28, outcome_29, _outcome_34] = attrs.outcomes

      assert outcome_28["outcome_label"] == "28C"
      assert outcome_28["yes_price"] == 0.35
      assert outcome_28["no_price"] == 0.65
      assert outcome_28["clob_token_ids"] == ["tok_yes_28", "tok_no_28"]
      assert outcome_28["volume"] == 3200.0
      assert outcome_28["liquidity"] == 500.0

      assert outcome_29["outcome_label"] == "29C"
      assert outcome_29["yes_price"] == 0.30
      assert outcome_29["no_price"] == 0.70
      assert outcome_29["clob_token_ids"] == ["tok_yes_29", "tok_no_29"]
    end

    test "parses edge bucket 'or below'" do
      {:ok, attrs} = EventParser.parse_event(@sample_event)

      below_outcome = Enum.find(attrs.outcomes, &(&1["outcome_label"] == "27C or below"))
      assert below_outcome != nil
      assert below_outcome["yes_price"] == 0.15
      assert below_outcome["no_price"] == 0.85
    end

    test "parses edge bucket 'or higher'" do
      {:ok, attrs} = EventParser.parse_event(@sample_event)

      higher_outcome = Enum.find(attrs.outcomes, &(&1["outcome_label"] == "34C or higher"))
      assert higher_outcome != nil
      assert higher_outcome["yes_price"] == 0.05
      assert higher_outcome["no_price"] == 0.95
    end

    test "returns error for invalid event format" do
      assert {:error, :invalid_event_format} = EventParser.parse_event(%{"bad" => "data"})
    end

    test "handles clobTokenIds as list" do
      event = %{
        "id" => 999,
        "slug" => "test-event",
        "title" => "Test March 10",
        "markets" => [
          %{
            "question" => "Will it be 28 degrees?",
            "outcomePrices" => ~s(["0.40", "0.60"]),
            "clobTokenIds" => ["tok_a", "tok_b"],
            "volume" => "100",
            "liquidity" => "50"
          }
        ]
      }

      {:ok, attrs} = EventParser.parse_event(event)
      [outcome] = attrs.outcomes
      assert outcome["clob_token_ids"] == ["tok_a", "tok_b"]
    end
  end
end
