defmodule WeatherEdge.Signals.Performance do
  @moduledoc """
  Computes historical signal accuracy and P&L statistics
  from resolved positions and accuracy records.
  """

  import Ecto.Query

  alias WeatherEdge.Repo
  alias WeatherEdge.Calibration.Accuracy
  alias WeatherEdge.Trading.Position

  @default_days 30

  @doc """
  Computes performance stats over the last N days.

  Returns a map with:
    - total_signals: total accuracy records
    - accuracy: overall accuracy percentage (correct / total)
    - accuracy_by_level: map of alert_level -> %{accuracy, count}
    - accuracy_by_station: map of station_code -> %{accuracy, pnl}
    - total_pnl: sum of realized P&L from closed positions
    - avg_edge: average best_edge from accuracy records
    - signal_history: list of recent signal results
  """
  def compute_stats(opts \\ []) do
    days = Keyword.get(opts, :days, @default_days)
    since = Date.utc_today() |> Date.add(-days)

    accuracy_records = load_accuracy_records(since)
    closed_positions = load_closed_positions(since)

    total_signals = length(accuracy_records)
    correct = Enum.count(accuracy_records, & &1.resolution_correct)
    accuracy = if total_signals > 0, do: correct / total_signals, else: 0.0

    avg_edge =
      case accuracy_records do
        [] ->
          0.0

        records ->
          edges = Enum.map(records, fn r -> r.best_edge || 0.0 end)
          Enum.sum(edges) / length(edges)
      end

    total_pnl =
      closed_positions
      |> Enum.map(fn p -> p.realized_pnl || 0.0 end)
      |> Enum.sum()

    %{
      total_signals: total_signals,
      accuracy: accuracy,
      accuracy_by_level: compute_accuracy_by_level(accuracy_records),
      accuracy_by_station: compute_accuracy_by_station(accuracy_records, closed_positions),
      total_pnl: total_pnl,
      avg_edge: avg_edge,
      signal_history: build_signal_history(accuracy_records, closed_positions)
    }
  end

  defp load_accuracy_records(since) do
    from(a in Accuracy,
      where: a.target_date >= ^since,
      order_by: [desc: a.target_date]
    )
    |> Repo.all()
  end

  defp load_closed_positions(since) do
    from(p in Position,
      where: p.status == "closed" and p.closed_at >= ^since,
      order_by: [desc: p.closed_at]
    )
    |> Repo.all()
  end

  defp compute_accuracy_by_level(records) do
    records
    |> Enum.filter(& &1.auto_buy_outcome)
    |> Enum.group_by(fn r ->
      cond do
        r.best_edge && r.best_edge >= 0.25 -> "extreme"
        r.best_edge && r.best_edge >= 0.15 -> "strong"
        r.best_edge && r.best_edge >= 0.08 -> "opportunity"
        true -> "other"
      end
    end)
    |> Map.new(fn {level, recs} ->
      total = length(recs)
      correct = Enum.count(recs, & &1.resolution_correct)
      acc = if total > 0, do: correct / total, else: 0.0
      {level, %{accuracy: acc, count: total}}
    end)
  end

  defp compute_accuracy_by_station(records, positions) do
    station_accuracy =
      records
      |> Enum.group_by(& &1.station_code)
      |> Map.new(fn {code, recs} ->
        total = length(recs)
        correct = Enum.count(recs, & &1.resolution_correct)
        acc = if total > 0, do: correct / total, else: 0.0
        {code, %{accuracy: acc, count: total}}
      end)

    station_pnl =
      positions
      |> Enum.group_by(& &1.station_code)
      |> Map.new(fn {code, pos} ->
        pnl = pos |> Enum.map(fn p -> p.realized_pnl || 0.0 end) |> Enum.sum()
        {code, pnl}
      end)

    Map.merge(station_accuracy, station_pnl, fn _code, acc_map, pnl ->
      Map.put(acc_map, :pnl, pnl)
    end)
    |> Map.new(fn {code, val} ->
      case val do
        %{accuracy: _, pnl: _} -> {code, val}
        %{accuracy: _} = m -> {code, Map.put(m, :pnl, 0.0)}
        pnl when is_number(pnl) -> {code, %{accuracy: 0.0, count: 0, pnl: pnl}}
      end
    end)
  end

  defp build_signal_history(accuracy_records, closed_positions) do
    position_map =
      closed_positions
      |> Enum.group_by(fn p -> {p.station_code, p.outcome_label} end)

    accuracy_records
    |> Enum.take(50)
    |> Enum.map(fn record ->
      position =
        Map.get(position_map, {record.station_code, record.auto_buy_outcome}, [])
        |> Enum.find(fn p ->
          Date.compare(DateTime.to_date(p.opened_at || p.inserted_at), record.target_date) in [:eq, :lt] and
            Date.compare(DateTime.to_date(p.closed_at || p.inserted_at), record.target_date) in [:eq, :gt]
        end)

      result =
        cond do
          position && position.realized_pnl && position.realized_pnl > 0 -> "won"
          position && position.realized_pnl && position.realized_pnl <= 0 -> "lost"
          position -> "sold"
          true -> "no_trade"
        end

      %{
        date: record.target_date,
        station: record.station_code,
        temp: record.auto_buy_outcome,
        edge: record.best_edge,
        result: result,
        pnl: if(position, do: position.realized_pnl, else: nil),
        correct: record.resolution_correct
      }
    end)
  end
end
