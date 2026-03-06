defmodule WeatherEdgeWeb.Components.StationCardComponent do
  use Phoenix.Component

  attr :station, :map, required: true
  attr :clusters, :list, default: []
  attr :balance, :float, default: nil

  def station_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-lg font-semibold text-zinc-900">
          <%= @station.code %> — <%= @station.city %>
        </h2>

        <div class="flex items-center gap-3">
          <label class="flex items-center gap-1.5 text-xs">
            <button
              phx-click="toggle_monitoring"
              phx-value-code={@station.code}
              class={"relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors #{if @station.monitoring_enabled, do: "bg-green-500", else: "bg-zinc-300"}"}
            >
              <span class={"pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition #{if @station.monitoring_enabled, do: "translate-x-4", else: "translate-x-0"}"} />
            </button>
            <span class={if @station.monitoring_enabled, do: "text-green-700", else: "text-zinc-400"}>
              Monitoring
            </span>
          </label>

          <label class="flex items-center gap-1.5 text-xs">
            <button
              phx-click="toggle_auto_buy"
              phx-value-code={@station.code}
              class={"relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors #{if @station.auto_buy_enabled, do: "bg-blue-500", else: "bg-zinc-300"}"}
            >
              <span class={"pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition #{if @station.auto_buy_enabled, do: "translate-x-4", else: "translate-x-0"}"} />
            </button>
            <span class={if @station.auto_buy_enabled, do: "text-blue-700", else: "text-zinc-400"}>
              Auto-Buy
            </span>
          </label>
        </div>
      </div>

      <div class="flex items-center gap-4 mb-3 text-xs text-zinc-500">
        <form phx-change="update_station_settings" phx-value-code={@station.code} class="flex items-center gap-3">
          <input type="hidden" name="code" value={@station.code} />
          <label class="flex items-center gap-1">
            Max Buy:
            <input
              type="number"
              name="max_buy_price"
              value={@station.max_buy_price}
              step="0.01"
              min="0"
              max="1"
              class="w-16 rounded border border-zinc-200 px-1.5 py-0.5 text-xs text-zinc-700"
              phx-debounce="500"
            />
          </label>
          <label class="flex items-center gap-1">
            Amount:
            <input
              type="number"
              name="buy_amount_usdc"
              value={@station.buy_amount_usdc}
              step="0.50"
              min="0"
              class="w-16 rounded border border-zinc-200 px-1.5 py-0.5 text-xs text-zinc-700"
              phx-debounce="500"
            />
            <span>USDC</span>
          </label>
        </form>

        <span :if={@balance} class="ml-auto text-xs text-zinc-400">
          Balance: $<%= format_balance(@balance) %>
        </span>
      </div>

      <div :if={@station.slug_pattern} class="mb-3 text-xs text-zinc-400">
        Next event: watching for "<%= @station.slug_pattern %>"
      </div>

      <div :if={@clusters != []} class="space-y-2">
        <h3 class="text-xs font-semibold text-zinc-500 uppercase tracking-wider">Active Events</h3>
        <div :for={cluster <- @clusters} class="ml-2 rounded border border-zinc-100 bg-zinc-50 p-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium text-zinc-700">
              <%= cluster.target_date %>
            </span>
            <.link
              navigate={"/stations/#{@station.code}/events/#{cluster.id}"}
              class="text-xs text-blue-600 hover:underline"
            >
              View Details
            </.link>
          </div>
        </div>
      </div>

      <p :if={@clusters == []} class="text-sm text-zinc-400">No active events</p>
    </div>
    """
  end

  defp format_balance(balance) when is_float(balance) do
    :erlang.float_to_binary(balance, decimals: 2)
  end

  defp format_balance(_), do: "0.00"
end
