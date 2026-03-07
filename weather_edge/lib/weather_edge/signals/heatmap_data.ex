defmodule WeatherEdge.Signals.HeatmapData do
  @moduledoc """
  Builds heatmap grid data from signals, showing best edge per station per date.
  """

  @doc """
  Builds a heatmap from a list of signal result maps.

  Returns a map with:
    - :dates - list of date maps with :date and :label keys (Today through +3d)
    - :stations - list of station maps with :code, :city, and :cells (one per date)

  Each cell is a map with: :best_edge, :signal_count, :has_position, :has_event
  """
  def build_heatmap(signals) do
    today = Date.utc_today()

    dates = [
      %{date: today, label: "Today"},
      %{date: Date.add(today, 1), label: "Tomorrow"},
      %{date: Date.add(today, 2), label: "+2d"},
      %{date: Date.add(today, 3), label: "+3d"}
    ]

    date_set = MapSet.new(Enum.map(dates, & &1.date))

    # Group signals by {station_code, target_date}
    grouped =
      signals
      |> Enum.filter(fn row -> row.cluster.target_date in date_set end)
      |> Enum.group_by(fn row -> {row.signal.station_code, row.cluster.target_date} end)

    # Get unique stations from signals (all dates, not just filtered)
    stations_map =
      signals
      |> Enum.reduce(%{}, fn row, acc ->
        code = row.signal.station_code
        Map.put_new(acc, code, row.station)
      end)

    station_rows =
      stations_map
      |> Enum.sort_by(fn {code, _} -> code end)
      |> Enum.map(fn {code, station} ->
        cells =
          Enum.map(dates, fn %{date: date} ->
            key = {code, date}

            case Map.get(grouped, key) do
              nil ->
                %{best_edge: nil, signal_count: 0, has_position: false, has_event: false}

              rows ->
                best_edge =
                  rows
                  |> Enum.map(fn r -> r.signal.edge || 0 end)
                  |> Enum.max()

                has_position = Enum.any?(rows, fn r -> r.position != nil end)

                %{
                  best_edge: best_edge,
                  signal_count: length(rows),
                  has_position: has_position,
                  has_event: true
                }
            end
          end)

        %{code: code, city: station && station.city, cells: cells}
      end)

    %{dates: dates, stations: station_rows}
  end
end
