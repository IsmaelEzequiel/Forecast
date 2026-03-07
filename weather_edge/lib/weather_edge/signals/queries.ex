defmodule WeatherEdge.Signals.Queries do
  @moduledoc """
  Query module for loading deduplicated, filtered signals with joins
  to market_clusters, stations, and positions.
  """

  import Ecto.Query

  alias WeatherEdge.Repo
  alias WeatherEdge.Signals.Signal

  @default_limit 20
  @default_offset 0

  @doc """
  Returns a list of maps with keys: signal, cluster, station, position, hours_to_resolution.
  Applies deduplication (latest per station_code + outcome_label + market_cluster_id)
  and dynamic filters.
  """
  def list_filtered_signals(filters, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, @default_offset)

    base_query(filters)
    |> apply_sort(filters)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
    |> Enum.map(&to_result_map/1)
  end

  @doc """
  Returns the count of filtered signals (same filters, no limit/offset).
  """
  def count_filtered_signals(filters) do
    base_query(filters)
    |> subquery()
    |> Repo.aggregate(:count)
  end

  defp base_query(filters) do
    latest_ids = latest_signal_ids_subquery()

    from(s in Signal,
      join: mc in assoc(s, :market_cluster),
      join: st in "stations",
      on: st.code == s.station_code,
      left_join: p in "positions",
      on:
        p.market_cluster_id == s.market_cluster_id and
          p.outcome_label == s.outcome_label and
          p.status == "open",
      where: s.id in subquery(latest_ids),
      where: mc.resolved == false,
      select: %{
        id: s.id,
        computed_at: s.computed_at,
        station_code: s.station_code,
        outcome_label: s.outcome_label,
        model_probability: s.model_probability,
        market_price: s.market_price,
        edge: s.edge,
        recommended_side: s.recommended_side,
        alert_level: s.alert_level,
        confidence: s.confidence,
        market_cluster_id: s.market_cluster_id,
        cluster_target_date: mc.target_date,
        cluster_title: mc.title,
        cluster_event_slug: mc.event_slug,
        cluster_outcomes: mc.outcomes,
        station_city: st.city,
        station_max_buy_price: st.max_buy_price,
        station_buy_amount_usdc: st.buy_amount_usdc,
        position_id: p.id,
        position_tokens: p.tokens,
        position_avg_buy_price: p.avg_buy_price,
        position_current_price: p.current_price,
        position_unrealized_pnl: p.unrealized_pnl,
        position_side: p.side
      }
    )
    |> apply_filters(filters)
  end

  defp latest_signal_ids_subquery do
    from(s in Signal,
      distinct: [s.station_code, s.outcome_label, s.market_cluster_id],
      order_by: [
        asc: s.station_code,
        asc: s.outcome_label,
        asc: s.market_cluster_id,
        desc: s.computed_at
      ],
      select: s.id
    )
  end

  defp apply_filters(query, filters) do
    query
    |> filter_stations(Map.get(filters, :stations, []))
    |> filter_min_edge(Map.get(filters, :min_edge))
    |> filter_side(Map.get(filters, :side, "all"))
    |> filter_max_price(Map.get(filters, :max_price))
    |> filter_alert_level(Map.get(filters, :alert_level, "all"))
    |> filter_resolution_date(Map.get(filters, :resolution_date, "all"))
    |> filter_has_position(Map.get(filters, :has_position, "all"))
    |> filter_actionable_only(Map.get(filters, :actionable_only, false))
  end

  defp filter_stations(query, []), do: query
  defp filter_stations(query, nil), do: query

  defp filter_stations(query, stations) when is_list(stations) do
    where(query, [s, ...], s.station_code in ^stations)
  end

  defp filter_min_edge(query, nil), do: query
  defp filter_min_edge(query, 0), do: query

  defp filter_min_edge(query, min_edge) do
    where(query, [s, ...], s.edge >= ^min_edge)
  end

  defp filter_side(query, "all"), do: query

  defp filter_side(query, side) when side in ["YES", "NO"] do
    where(query, [s, ...], s.recommended_side == ^side)
  end

  defp filter_side(query, _), do: query

  defp filter_max_price(query, nil), do: query

  defp filter_max_price(query, max_price) do
    where(query, [s, ...], s.market_price <= ^max_price)
  end

  defp filter_alert_level(query, "all"), do: query

  defp filter_alert_level(query, level) when is_binary(level) do
    where(query, [s, ...], s.alert_level == ^level)
  end

  defp filter_alert_level(query, _), do: query

  defp filter_resolution_date(query, "all"), do: query

  defp filter_resolution_date(query, date_filter) do
    today = Date.utc_today()

    target =
      case date_filter do
        "today" -> today
        "tomorrow" -> Date.add(today, 1)
        "+2d" -> Date.add(today, 2)
        "+3d" -> Date.add(today, 3)
        _ -> nil
      end

    if target do
      where(query, [_s, mc, ...], mc.target_date == ^target)
    else
      query
    end
  end

  defp filter_has_position(query, "all"), do: query

  defp filter_has_position(query, "with_position") do
    where(query, [..., p], not is_nil(p.id))
  end

  defp filter_has_position(query, "without_position") do
    where(query, [..., p], is_nil(p.id))
  end

  defp filter_has_position(query, _), do: query

  defp filter_actionable_only(query, false), do: query
  defp filter_actionable_only(query, nil), do: query

  defp filter_actionable_only(query, true) do
    where(query, [_s, _mc, st, ...], st.max_buy_price >= 0)
    |> where([s, _mc, st, ...], s.market_price <= st.max_buy_price)
  end

  defp apply_sort(query, filters) do
    case Map.get(filters, :sort_by, "edge_desc") do
      "edge_desc" -> order_by(query, [s, ...], desc: s.edge)
      "edge_asc" -> order_by(query, [s, ...], asc: s.edge)
      "model_prob_desc" -> order_by(query, [s, ...], desc: s.model_probability)
      "time_to_resolution" -> order_by(query, [_s, mc, ...], asc: mc.target_date)
      "price_asc" -> order_by(query, [s, ...], asc: s.market_price)
      "newest" -> order_by(query, [s, ...], desc: s.computed_at)
      _ -> order_by(query, [s, ...], desc: s.edge)
    end
  end

  defp to_result_map(row) do
    now = DateTime.utc_now()
    target_date = row.cluster_target_date

    hours_to_resolution =
      if target_date do
        target_datetime =
          DateTime.new!(target_date, ~T[23:59:59], "Etc/UTC")

        DateTime.diff(target_datetime, now, :hour) |> max(0)
      else
        nil
      end

    %{
      signal: %{
        id: row.id,
        computed_at: row.computed_at,
        station_code: row.station_code,
        outcome_label: row.outcome_label,
        model_probability: row.model_probability,
        market_price: row.market_price,
        edge: row.edge,
        recommended_side: row.recommended_side,
        alert_level: row.alert_level,
        confidence: row.confidence,
        market_cluster_id: row.market_cluster_id
      },
      cluster: %{
        id: row.market_cluster_id,
        target_date: row.cluster_target_date,
        title: row.cluster_title,
        event_slug: row.cluster_event_slug,
        outcomes: row.cluster_outcomes
      },
      station: %{
        code: row.station_code,
        city: row.station_city,
        max_buy_price: row.station_max_buy_price,
        buy_amount_usdc: row.station_buy_amount_usdc
      },
      position:
        if row.position_id do
          %{
            id: row.position_id,
            tokens: row.position_tokens,
            avg_buy_price: row.position_avg_buy_price,
            current_price: row.position_current_price,
            unrealized_pnl: row.position_unrealized_pnl,
            side: row.position_side
          }
        else
          nil
        end,
      hours_to_resolution: hours_to_resolution
    }
  end
end
