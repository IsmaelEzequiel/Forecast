defmodule WeatherEdgeWeb.Components.HeaderComponent do
  use Phoenix.Component

  attr :balance, :float, default: nil
  attr :wallet_address, :string, default: nil

  def dashboard_header(assigns) do
    ~H"""
    <header class="flex items-center justify-between rounded-lg border border-zinc-200 bg-white p-4 shadow-sm">
      <h1 class="text-xl font-bold tracking-wide text-zinc-900">WEATHER EDGE</h1>

      <div class="flex items-center gap-4">
        <span :if={@balance} class="text-sm font-medium text-zinc-600">
          $<%= format_balance(@balance) %> USDC
        </span>

        <span :if={@wallet_address} class="text-xs font-mono text-zinc-400">
          <%= truncate_address(@wallet_address) %>
        </span>

        <button
          phx-click="toggle_add_station_modal"
          class="rounded-lg bg-zinc-900 px-3 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
        >
          + Add Station
        </button>

        <.link navigate="/settings" class="text-sm text-zinc-500 hover:text-zinc-700">
          Settings
        </.link>
      </div>
    </header>
    """
  end

  defp format_balance(balance) when is_float(balance) do
    :erlang.float_to_binary(balance, decimals: 2)
  end

  defp format_balance(_), do: "0.00"

  defp truncate_address(address) when is_binary(address) and byte_size(address) >= 10 do
    "#{String.slice(address, 0, 6)}...#{String.slice(address, -4, 4)}"
  end

  defp truncate_address(address), do: address
end
