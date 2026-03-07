defmodule WeatherEdge.Signals.GroupedView do
  @moduledoc """
  Groups signals by event (station_code + market_cluster_id) for the grouped view mode.
  """

  @doc """
  Groups a list of signal result maps by {station_code, market_cluster_id}.
  Returns a list of group structs sorted by soonest resolution.
  """
  def group_signals_by_event(signals) do
    signals
    |> Enum.group_by(fn row -> {row.signal.station_code, row.cluster.id} end)
    |> Enum.map(fn {{station_code, _cluster_id}, rows} ->
      first = hd(rows)
      cluster = first.cluster
      station = first.station

      sorted_by_edge = Enum.sort_by(rows, fn r -> r.signal.edge || 0 end, :desc)

      best_play =
        sorted_by_edge
        |> Enum.find(fn r -> r.signal.recommended_side == "YES" end)
        |> then(fn nil -> hd(sorted_by_edge); play -> play end)

      hedge_options =
        Enum.filter(rows, fn r -> r.signal.alert_level == "safe_no" end)
        |> Enum.sort_by(fn r -> r.signal.edge || 0 end, :desc)

      best_play_id = best_play.signal.id
      hedge_ids = MapSet.new(Enum.map(hedge_options, fn r -> r.signal.id end))

      other_signals =
        Enum.filter(rows, fn r ->
          r.signal.id != best_play_id and not MapSet.member?(hedge_ids, r.signal.id)
        end)

      cluster_health = sum_yes_prices(cluster.outcomes)

      %{
        station_code: station_code,
        station: station,
        cluster: cluster,
        best_play: best_play,
        hedge_options: hedge_options,
        other_signals: other_signals,
        cluster_health: cluster_health,
        hours_to_resolution: first.hours_to_resolution,
        signal_count: length(rows)
      }
    end)
    |> Enum.sort_by(fn g -> g.hours_to_resolution || 999 end, :asc)
  end

  defp sum_yes_prices(outcomes) when is_list(outcomes) do
    Enum.reduce(outcomes, 0.0, fn o, acc ->
      acc + (o["price"] || o["yes_price"] || 0)
    end)
  end

  defp sum_yes_prices(_), do: 0.0
end
