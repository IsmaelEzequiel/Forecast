defmodule WeatherEdgeWeb.SignalsLive do
  use WeatherEdgeWeb, :live_view

  alias WeatherEdge.PubSubHelper

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

    {:ok,
     assign(socket,
       filters: default_filters(),
       signals: [],
       total_count: 0,
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
        <p class="text-sm text-zinc-500 dark:text-zinc-400">Filter bar placeholder</p>
      </div>

      <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
        <p class="text-sm text-zinc-500 dark:text-zinc-400">
          Signals content area - <%= @view_mode %> view | <%= @total_count %> signals
        </p>
      </div>
    </div>
    """
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
