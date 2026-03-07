defmodule WeatherEdgeWeb.Components.StationCardComponent do
  use Phoenix.Component

  import WeatherEdgeWeb.Components.EventCardComponent

  attr :station, :map, required: true
  attr :clusters, :list, default: []
  attr :positions_by_cluster, :map, default: %{}
  attr :balance, :float, default: nil

  def station_card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center gap-2">
          <h2 class="text-sm font-semibold text-zinc-900">
            <%= @station.code %> — <%= @station.city %>
          </h2>
          <% {peak, _hrs} = WeatherEdge.Timezone.PeakCalculator.peak_status(@station.longitude) %>
          <span class={["text-xs px-1.5 py-0.5 rounded-full font-medium", peak_class(peak)]}>
            <%= peak_icon(peak) %> <%= WeatherEdge.Timezone.PeakCalculator.status_label(peak) %>
          </span>
        </div>

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

          <button
            phx-click="delete_station"
            phx-value-code={@station.code}
            data-confirm={"Delete station #{@station.code}? This cannot be undone."}
            class="text-xs text-red-400 hover:text-red-600"
          >
            &times;
          </button>
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
        <.event_card
          :for={cluster <- @clusters}
          cluster={cluster}
          position={Map.get(@positions_by_cluster, cluster.id)}
          station_code={@station.code}
        />
      </div>

      <div :if={@clusters == []} class="flex items-center gap-3">
        <p class="text-sm text-zinc-400">No active events</p>
        <button
          phx-click="scan_station"
          phx-value-code={@station.code}
          class="text-xs text-blue-600 hover:text-blue-800 underline"
        >
          Scan Now
        </button>
      </div>
    </div>
    """
  end

  defp format_balance(balance) when is_number(balance) do
    :erlang.float_to_binary(balance / 1, decimals: 2)
  end

  defp format_balance(_), do: "0.00"

  defp peak_class(:post_peak), do: "bg-emerald-100 text-emerald-700"
  defp peak_class(:near_peak), do: "bg-amber-100 text-amber-700"
  defp peak_class(:pre_peak), do: "bg-sky-100 text-sky-700"
  defp peak_class(:night), do: "bg-zinc-100 text-zinc-500"

  defp peak_icon(:post_peak), do: "☀"
  defp peak_icon(:near_peak), do: "⛅"
  defp peak_icon(:pre_peak), do: "🌤"
  defp peak_icon(:night), do: "🌙"
end
