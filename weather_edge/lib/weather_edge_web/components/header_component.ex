defmodule WeatherEdgeWeb.Components.HeaderComponent do
  use Phoenix.Component

  attr :balance, :float, default: nil
  attr :wallet_address, :string, default: nil

  def dashboard_header(assigns) do
    ~H"""
    <header class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-3 sm:p-4 shadow-sm space-y-2 sm:space-y-0">
      <div class="flex items-center justify-between">
        <h1 class="text-base sm:text-xl font-bold tracking-wide text-zinc-900 dark:text-zinc-100">WEATHER EDGE</h1>

        <div class="flex items-center gap-2 sm:gap-4">
          <span :if={@balance} class="text-xs sm:text-sm font-medium text-zinc-600 dark:text-zinc-300">
            $<%= format_balance(@balance) %>
          </span>

          <span :if={@wallet_address} class="hidden sm:inline text-xs font-mono text-zinc-400">
            <%= truncate_address(@wallet_address) %>
          </span>

          <button
            phx-click="toggle_add_station_modal"
            class="rounded-lg bg-zinc-900 dark:bg-zinc-100 px-2 sm:px-3 py-1.5 sm:py-2 text-xs sm:text-sm font-semibold text-white dark:text-zinc-900 hover:bg-zinc-700 dark:hover:bg-zinc-300"
          >
            + Add
          </button>

          <button
            id="dark-mode-toggle"
            phx-hook="DarkMode"
            class="rounded-lg p-1.5 sm:p-2 text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-200 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
            title="Toggle dark mode"
          >
            <svg class="w-4 h-4 sm:w-5 sm:h-5 hidden dark:block" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 3v2.25m6.364.386l-1.591 1.591M21 12h-2.25m-.386 6.364l-1.591-1.591M12 18.75V21m-4.773-4.227l-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0z" />
            </svg>
            <svg class="w-4 h-4 sm:w-5 sm:h-5 block dark:hidden" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21.752 15.002A9.718 9.718 0 0118 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 003 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 009.002-5.998z" />
            </svg>
          </button>
        </div>
      </div>

      <nav class="flex items-center gap-1 overflow-x-auto pb-1 sm:pb-0 -mx-1 px-1">
        <.link navigate="/" class="whitespace-nowrap text-xs sm:text-sm text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-200 px-1.5 py-0.5">
          Dashboard
        </.link>
        <.link navigate="/positions" class="whitespace-nowrap text-xs sm:text-sm text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-200 px-1.5 py-0.5">
          Positions
        </.link>
        <.link href="/admin/dashboard/oban" class="whitespace-nowrap text-xs sm:text-sm text-zinc-500 hover:text-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-200 px-1.5 py-0.5">
          Admin
        </.link>
      </nav>
    </header>
    """
  end

  defp format_balance(balance) when is_number(balance) do
    formatted = :erlang.float_to_binary(balance / 1, decimals: 2)

    [integer_part, decimal_part] = String.split(formatted, ".")

    grouped =
      integer_part
      |> String.reverse()
      |> String.to_charlist()
      |> Enum.chunk_every(3)
      |> Enum.join(",")
      |> String.reverse()

    "#{grouped}.#{decimal_part}"
  end

  defp format_balance(_), do: "0.00"

  defp truncate_address(address) when is_binary(address) and byte_size(address) >= 10 do
    "#{String.slice(address, 0, 6)}...#{String.slice(address, -4, 4)}"
  end

  defp truncate_address(address), do: address
end
