defmodule WeatherEdgeWeb.SignalsLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.PubSubHelper
  alias WeatherEdge.Signals.Queries

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
       wallet_address: wallet_address
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.dashboard_header balance={@balance} wallet_address={@wallet_address} />

      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <div class="flex items-center justify-between">
          <p class="text-sm text-zinc-500 dark:text-zinc-400">Filter bar placeholder</p>
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
