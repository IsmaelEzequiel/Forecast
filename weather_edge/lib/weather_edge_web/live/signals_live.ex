defmodule WeatherEdgeWeb.SignalsLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.PubSubHelper
  alias WeatherEdge.Signals.Queries
  alias WeatherEdge.Stations

  import WeatherEdgeWeb.Components.HeaderComponent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSubHelper.subscribe(PubSubHelper.signals_new())
      PubSubHelper.subscribe(PubSubHelper.portfolio_balance_update())
      PubSubHelper.subscribe(PubSubHelper.portfolio_position_update())
    end

    wallet_address = Application.get_env(:weather_edge, :polymarket)[:wallet_address]
    cached_balance = :persistent_term.get(:sidecar_balance, nil)

    filters = default_filters()

    station_codes =
      if connected?(socket) do
        Stations.list_stations() |> Enum.map(& &1.code) |> Enum.sort()
      else
        []
      end

    {signals, total_count} =
      if connected?(socket) do
        {Queries.list_filtered_signals(filters), Queries.count_filtered_signals(filters)}
      else
        {[], 0}
      end

    {:ok,
     assign(socket,
       filters: filters,
       signals: signals,
       total_count: total_count,
       selected: MapSet.new(),
       view_mode: :table,
       detail_signal_id: nil,
       balance: cached_balance,
       wallet_address: wallet_address,
       station_codes: station_codes
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.dashboard_header balance={@balance} wallet_address={@wallet_address} />

      <div class="sticky top-0 z-30 rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4 space-y-3">
        <div class="flex items-center justify-between">
          <.filter_bar filters={@filters} station_codes={@station_codes} total_count={@total_count} signals_count={length(@signals)} />
          <.view_mode_toggle view_mode={@view_mode} />
        </div>
      </div>

      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <p class="text-sm text-zinc-500 dark:text-zinc-400">
          Signals content area - <%= @view_mode %> view | Showing <%= length(@signals) %> of <%= @total_count %> signals
        </p>
      </div>
    </div>
    """
  end

  defp filter_bar(assigns) do
    active_count = count_active_filters(assigns.filters)
    assigns = assign(assigns, :active_count, active_count)

    ~H"""
    <div class="flex-1 space-y-3">
      <div class="flex flex-wrap gap-3 items-end">
        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Stations</label>
          <select
            name="stations"
            multiple
            phx-change="update_filter"
            class="block w-40 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option
              :for={code <- @station_codes}
              value={code}
              selected={code in @filters.stations}
            >
              <%= code %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Min Edge %</label>
          <input
            type="number"
            name="min_edge"
            value={@filters.min_edge}
            min="0"
            max="60"
            step="1"
            phx-change="update_filter"
            class="block w-20 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Resolution</label>
          <select
            name="resolution_date"
            phx-change="update_filter"
            class="block w-28 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option :for={{val, label} <- [{"all", "All"}, {"today", "Today"}, {"tomorrow", "Tomorrow"}, {"+2d", "+2d"}, {"+3d", "+3d"}]} value={val} selected={@filters.resolution_date == val}>
              <%= label %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Side</label>
          <select
            name="side"
            phx-change="update_filter"
            class="block w-20 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option :for={{val, label} <- [{"all", "All"}, {"YES", "YES"}, {"NO", "NO"}]} value={val} selected={@filters.side == val}>
              <%= label %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Max Price</label>
          <input
            type="number"
            name="max_price"
            value={@filters.max_price}
            min="0"
            max="1"
            step="0.01"
            placeholder="Any"
            phx-change="update_filter"
            class="block w-20 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          />
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Alert Level</label>
          <select
            name="alert_level"
            phx-change="update_filter"
            class="block w-28 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option
              :for={{val, label} <- [{"all", "All"}, {"extreme", "Extreme"}, {"strong", "Strong"}, {"opportunity", "Opportunity"}, {"safe_no", "Safe NO"}]}
              value={val}
              selected={@filters.alert_level == val}
            >
              <%= label %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Sort</label>
          <select
            name="sort_by"
            phx-change="update_filter"
            class="block w-36 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option
              :for={{val, label} <- [{"edge_desc", "Highest Edge"}, {"price_asc", "Lowest Price"}, {"model_prob_desc", "Highest Model Prob"}, {"time_to_resolution", "Soonest Resolution"}, {"newest", "Newest"}]}
              value={val}
              selected={@filters.sort_by == val}
            >
              <%= label %>
            </option>
          </select>
        </div>

        <div class="space-y-1">
          <label class="text-xs text-zinc-500 dark:text-zinc-400">Position</label>
          <select
            name="has_position"
            phx-change="update_filter"
            class="block w-32 text-xs rounded border border-zinc-300 dark:border-zinc-600 bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 p-1.5"
          >
            <option :for={{val, label} <- [{"all", "All"}, {"with_position", "With Position"}, {"without_position", "Without Position"}]} value={val} selected={@filters.has_position == val}>
              <%= label %>
            </option>
          </select>
        </div>

        <label class="flex items-center gap-1.5 pb-0.5 cursor-pointer">
          <input
            type="checkbox"
            name="actionable_only"
            checked={@filters.actionable_only}
            phx-click="toggle_actionable"
            class="rounded border-zinc-300 dark:border-zinc-600 text-blue-600"
          />
          <span class="text-xs text-zinc-600 dark:text-zinc-400">Actionable Only</span>
        </label>
      </div>

      <div class="flex items-center gap-2 text-xs text-zinc-500 dark:text-zinc-400">
        <span>Active: <%= @active_count %> filters | Showing <%= @signals_count %> of <%= @total_count %> signals</span>
        <button
          :if={@active_count > 0}
          phx-click="clear_filters"
          class="text-blue-600 dark:text-blue-400 hover:underline"
        >
          Clear All
        </button>
      </div>
    </div>
    """
  end

  defp view_mode_toggle(assigns) do
    ~H"""
    <div class="flex items-center rounded-lg border border-zinc-200 dark:border-zinc-700 overflow-hidden">
      <button
        :for={{mode, label} <- [table: "Table", grouped: "Grouped", heatmap: "Heatmap"]}
        phx-click="set_view"
        phx-value-mode={mode}
        class={[
          "px-3 py-1.5 text-xs font-medium transition-colors",
          if(@view_mode == mode,
            do: "bg-blue-600 text-white",
            else: "bg-white dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400 hover:bg-zinc-50 dark:hover:bg-zinc-700"
          )
        ]}
      >
        <%= label %>
      </button>
    </div>
    """
  end

  @impl true
  def handle_event("set_view", %{"mode" => mode}, socket) when mode in ~w(table grouped heatmap) do
    {:noreply, assign(socket, :view_mode, String.to_existing_atom(mode))}
  end

  def handle_event("update_filter", params, socket) do
    filters = socket.assigns.filters

    updated_filters =
      filters
      |> maybe_update_stations(params)
      |> maybe_update_string(params, "resolution_date", :resolution_date)
      |> maybe_update_string(params, "side", :side)
      |> maybe_update_string(params, "alert_level", :alert_level)
      |> maybe_update_string(params, "sort_by", :sort_by)
      |> maybe_update_string(params, "has_position", :has_position)
      |> maybe_update_number(params, "min_edge", :min_edge)
      |> maybe_update_float(params, "max_price", :max_price)

    reload_signals(socket, updated_filters)
  end

  def handle_event("toggle_actionable", _params, socket) do
    filters = Map.update!(socket.assigns.filters, :actionable_only, &(!&1))
    reload_signals(socket, filters)
  end

  def handle_event("clear_filters", _params, socket) do
    reload_signals(socket, default_filters())
  end

  defp reload_signals(socket, filters) do
    signals = Queries.list_filtered_signals(filters)
    total_count = Queries.count_filtered_signals(filters)

    {:noreply,
     assign(socket,
       filters: filters,
       signals: signals,
       total_count: total_count
     )}
  end

  defp maybe_update_stations(filters, %{"stations" => stations}) when is_list(stations) do
    %{filters | stations: stations}
  end

  defp maybe_update_stations(filters, _), do: filters

  defp maybe_update_string(filters, params, key, field) do
    case Map.get(params, key) do
      nil -> filters
      val -> Map.put(filters, field, val)
    end
  end

  defp maybe_update_number(filters, params, key, field) do
    case Map.get(params, key) do
      nil -> filters
      "" -> Map.put(filters, field, nil)
      val ->
        case Integer.parse(to_string(val)) do
          {num, _} -> Map.put(filters, field, num)
          :error -> filters
        end
    end
  end

  defp maybe_update_float(filters, params, key, field) do
    case Map.get(params, key) do
      nil -> filters
      "" -> Map.put(filters, field, nil)
      val ->
        case Float.parse(to_string(val)) do
          {num, _} -> Map.put(filters, field, num)
          :error -> filters
        end
    end
  end

  defp count_active_filters(filters) do
    defaults = default_filters()

    Enum.count(Map.keys(defaults), fn key ->
      Map.get(filters, key) != Map.get(defaults, key)
    end)
  end

  defp default_filters do
    %{
      stations: [],
      min_edge: 8,
      resolution_date: "all",
      side: "all",
      max_price: nil,
      alert_level: "all",
      sort_by: "edge_desc",
      actionable_only: false,
      has_position: "all"
    }
  end
end
