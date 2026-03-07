defmodule WeatherEdge.Markets.EventParser do
  @moduledoc """
  Parses Gamma API event JSON into MarketCluster-compatible attributes.
  """

  @doc """
  Parses a raw Gamma API event map into attributes for a MarketCluster record.

  Returns `{:ok, attrs}` with extracted fields or `{:error, reason}` if parsing fails.
  """
  @spec parse_event(map()) :: {:ok, map()} | {:error, term()}
  def parse_event(%{"id" => event_id, "slug" => slug, "title" => title, "markets" => markets})
      when is_list(markets) do
    target_date = extract_target_date(title, slug)
    station_code = extract_station_code(title, slug)
    outcomes = Enum.map(markets, &parse_market/1)

    attrs = %{
      event_id: to_string(event_id),
      event_slug: slug,
      title: title,
      target_date: target_date,
      station_code: station_code,
      outcomes: outcomes
    }

    {:ok, attrs}
  end

  def parse_event(_), do: {:error, :invalid_event_format}

  defp parse_market(market) do
    question = Map.get(market, "question", "")
    tokens = extract_clob_tokens(market)

    %{
      "question" => question,
      "outcome_label" => extract_degree_label(question),
      "yes_price" => parse_float(Map.get(market, "outcomePrices")),
      "no_price" => parse_no_price(Map.get(market, "outcomePrices")),
      "clob_token_ids" => tokens,
      "volume" => parse_number(Map.get(market, "volume", "0")),
      "liquidity" => parse_number(Map.get(market, "liquidity", "0"))
    }
  end

  defp extract_degree_label(question) do
    cond do
      Regex.match?(~r/(\d+)\s*degrees?\s*or\s*below/i, question) ->
        [_, degrees] = Regex.run(~r/(\d+)\s*degrees?\s*or\s*below/i, question)
        "#{degrees}C or below"

      Regex.match?(~r/(\d+)\s*degrees?\s*or\s*higher/i, question) ->
        [_, degrees] = Regex.run(~r/(\d+)\s*degrees?\s*or\s*higher/i, question)
        "#{degrees}C or higher"

      Regex.match?(~r/(\d+)\s*degrees?/i, question) ->
        [_, degrees] = Regex.run(~r/(\d+)\s*degrees?/i, question)
        "#{degrees}C"

      true ->
        question
    end
  end

  defp extract_clob_tokens(market) do
    token_ids = Map.get(market, "clobTokenIds", "")

    case token_ids do
      ids when is_binary(ids) and ids != "" ->
        ids
        |> String.replace(~r/[\[\]\s"]/, "")
        |> String.split(",", trim: true)

      ids when is_list(ids) ->
        ids

      _ ->
        []
    end
  end

  defp extract_target_date(title, slug) do
    date_regex = ~r/(\w+)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s*(\d{4}))?/

    source = "#{title} #{slug}"

    case Regex.run(date_regex, source) do
      [_, month_str, day_str | rest] ->
        year = case rest do
          [year_str] when year_str != "" -> String.to_integer(year_str)
          _ -> Date.utc_today().year
        end

        month = month_to_number(String.downcase(month_str))

        if month do
          day = String.to_integer(day_str)
          case Date.new(year, month, day) do
            {:ok, date} -> date
            _ -> nil
          end
        end

      _ ->
        nil
    end
  end

  defp extract_station_code(_title, _slug), do: nil

  defp month_to_number("january"), do: 1
  defp month_to_number("jan"), do: 1
  defp month_to_number("february"), do: 2
  defp month_to_number("feb"), do: 2
  defp month_to_number("march"), do: 3
  defp month_to_number("mar"), do: 3
  defp month_to_number("april"), do: 4
  defp month_to_number("apr"), do: 4
  defp month_to_number("may"), do: 5
  defp month_to_number("june"), do: 6
  defp month_to_number("jun"), do: 6
  defp month_to_number("july"), do: 7
  defp month_to_number("jul"), do: 7
  defp month_to_number("august"), do: 8
  defp month_to_number("aug"), do: 8
  defp month_to_number("september"), do: 9
  defp month_to_number("sep"), do: 9
  defp month_to_number("october"), do: 10
  defp month_to_number("oct"), do: 10
  defp month_to_number("november"), do: 11
  defp month_to_number("nov"), do: 11
  defp month_to_number("december"), do: 12
  defp month_to_number("dec"), do: 12
  defp month_to_number(_), do: nil

  defp parse_float(prices) when is_binary(prices) do
    case Jason.decode(prices) do
      {:ok, [yes_str | _]} -> safe_parse_float(yes_str)
      _ -> 0.0
    end
  end

  defp parse_float(_), do: 0.0

  defp parse_no_price(prices) when is_binary(prices) do
    case Jason.decode(prices) do
      {:ok, [_, no_str | _]} -> safe_parse_float(no_str)
      {:ok, [yes_str]} -> 1.0 - safe_parse_float(yes_str)
      _ -> 0.0
    end
  end

  defp parse_no_price(_), do: 0.0

  defp safe_parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp safe_parse_float(val) when is_float(val), do: val
  defp safe_parse_float(val) when is_integer(val), do: val / 1
  defp safe_parse_float(_), do: 0.0

  defp parse_number(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_number(val) when is_number(val), do: val
  defp parse_number(_), do: 0.0
end
