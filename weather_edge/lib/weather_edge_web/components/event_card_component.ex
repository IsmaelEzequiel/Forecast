defmodule WeatherEdgeWeb.Components.EventCardComponent do
  use Phoenix.Component

  attr :cluster, :map, required: true
  attr :position, :map, default: nil
  attr :station_code, :string, required: true

  def event_card(assigns) do
    assigns =
      assigns
      |> assign(:days_until, days_until_resolution(assigns.cluster.target_date))
      |> assign(:pnl_pct, calc_pnl_pct(assigns.position))

    ~H"""
    <div class={"rounded border p-3 #{if @position && @position.auto_bought, do: "border-blue-300 bg-blue-50 dark:border-blue-700 dark:bg-blue-950/30", else: "border-zinc-100 bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800"}"}>
      <div class="flex items-center justify-between mb-2">
        <div>
          <span class="text-sm font-medium text-zinc-700 dark:text-zinc-300">
            <%= Calendar.strftime(@cluster.target_date, "%b %-d") %>
          </span>
          <span class="text-xs text-zinc-400 ml-1">
            (<%= resolution_label(@days_until) %>)
          </span>
        </div>
        <div class="flex items-center gap-2">
          <.link
            navigate={"/stations/#{@station_code}/events/#{@cluster.id}"}
            class="text-xs text-blue-600 dark:text-blue-400 hover:underline"
          >
            View Details
          </.link>
          <button
            phx-click="delete_cluster"
            phx-value-cluster_id={@cluster.id}
            data-confirm="Are you sure you want to delete this event?"
            class="text-xs text-red-400 hover:text-red-600"
          >
            &times;
          </button>
        </div>
      </div>

      <%= if @position do %>
        <div class="mb-2 space-y-1">
          <div class="flex items-center justify-between text-xs">
            <span class="text-zinc-500 dark:text-zinc-400">
              <%= @position.outcome_label %> (<%= @position.side %>)
            </span>
            <span class="text-zinc-500 dark:text-zinc-400">
              <%= format_float(@position.tokens) %> tokens
            </span>
          </div>
          <div class="flex items-center justify-between text-xs">
            <span class="text-zinc-500 dark:text-zinc-400">
              Buy: $<%= format_float(@position.avg_buy_price) %>
              <span :if={@position.current_price}>
                / Now: $<%= format_float(@position.current_price) %>
              </span>
            </span>
            <span :if={@pnl_pct} class={pnl_color(@pnl_pct)}>
              <%= if @pnl_pct >= 0, do: "+", else: "" %><%= format_float(@pnl_pct) %>%
            </span>
          </div>

          <div :if={@position.recommendation} class="text-xs font-medium text-amber-700 dark:text-amber-400 mt-1">
            <%= @position.recommendation %>
          </div>

          <div :if={@position.auto_bought} class="text-xs text-blue-600 dark:text-blue-400 mt-1">
            Auto-bought
          </div>

          <div class="flex gap-2 mt-2">
            <button
              phx-click="sell_position"
              phx-value-position_id={@position.id}
              class="rounded bg-red-500 px-2.5 py-1 text-xs font-medium text-white hover:bg-red-600"
            >
              SELL
            </button>
            <button
              class="rounded bg-zinc-200 dark:bg-zinc-700 px-2.5 py-1 text-xs font-medium text-zinc-700 dark:text-zinc-300 hover:bg-zinc-300 dark:hover:bg-zinc-600"
              disabled
            >
              HOLD
            </button>
          </div>
        </div>
      <% end %>

      <div :if={@cluster.outcomes} class="text-xs text-zinc-500 dark:text-zinc-400">
        <span class="font-medium text-zinc-600 dark:text-zinc-300">Top outcomes:</span>
        <%= for outcome <- top_outcomes(@cluster.outcomes, 2) do %>
          <span class="ml-1"><%= outcome["outcome_label"] %> (<%= format_price(outcome["yes_price"]) %>)</span>
        <% end %>
      </div>
    </div>
    """
  end

  defp days_until_resolution(target_date) do
    Date.diff(target_date, Date.utc_today())
  end

  defp resolution_label(days) when days < 0, do: "resolved"
  defp resolution_label(0), do: "resolves today"
  defp resolution_label(1), do: "resolves tomorrow"
  defp resolution_label(days), do: "resolves in #{days} days"

  defp calc_pnl_pct(nil), do: nil

  defp calc_pnl_pct(%{unrealized_pnl: pnl, total_cost_usdc: cost})
       when is_number(pnl) and is_number(cost) and cost > 0 do
    pnl / cost * 100
  end

  defp calc_pnl_pct(_), do: nil

  defp pnl_color(pct) when pct >= 0, do: "font-medium text-green-600"
  defp pnl_color(_), do: "font-medium text-red-600"

  defp format_float(val) when is_float(val), do: :erlang.float_to_binary(val, decimals: 2)
  defp format_float(val) when is_integer(val), do: Integer.to_string(val)
  defp format_float(_), do: "0.00"

  defp format_price(price) when is_number(price), do: "#{:erlang.float_to_binary(price * 1.0, decimals: 2)}"
  defp format_price(price) when is_binary(price) do
    case Float.parse(price) do
      {val, _} -> format_price(val)
      :error -> price
    end
  end
  defp format_price(_), do: "?"

  defp top_outcomes(outcomes, n) when is_list(outcomes) do
    outcomes
    |> Enum.sort_by(fn o ->
      case o["yes_price"] do
        p when is_number(p) -> -p
        p when is_binary(p) ->
          case Float.parse(p) do
            {val, _} -> -val
            :error -> 0
          end
        _ -> 0
      end
    end)
    |> Enum.take(n)
  end

  defp top_outcomes(_, _), do: []
end
