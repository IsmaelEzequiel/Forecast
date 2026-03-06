defmodule WeatherEdgeWeb.Components.SignalFeedComponent do
  use Phoenix.Component

  @doc """
  Renders a real-time signal feed showing mispricing signals and auto-buy events.
  """
  attr :signals, :list, required: true

  def signal_feed(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-4">
      <h3 class="text-sm font-semibold text-zinc-700 mb-3">Signal Feed</h3>

      <div :if={@signals == []} class="text-sm text-zinc-400">
        No signals yet. Mispricing signals will appear here in real-time.
      </div>

      <div :if={@signals != []} class="space-y-2 max-h-[600px] overflow-y-auto">
        <div
          :for={signal <- Enum.take(@signals, 50)}
          class={[
            "rounded-md border px-3 py-2 text-sm",
            signal_border_class(signal)
          ]}
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class={["inline-block w-2 h-2 rounded-full", signal_dot_class(signal)]}></span>
              <span class="font-mono text-xs text-zinc-500">
                {format_timestamp(signal)}
              </span>
              <span class="font-semibold text-zinc-700">{signal_station_code(signal)}</span>
            </div>
            <span class={["text-xs font-medium px-2 py-0.5 rounded-full", alert_badge_class(signal)]}>
              {signal_alert_text(signal)}
            </span>
          </div>

          <div class="mt-1 flex items-center gap-3 text-xs text-zinc-600">
            <%= if signal_type(signal) == :auto_buy do %>
              <span class="font-medium text-indigo-600">AUTO-BUY</span>
              <span>{signal_outcome(signal)}</span>
              <span>@ {signal_price(signal)}</span>
            <% else %>
              <span>{signal_outcome(signal)}</span>
              <span>Price: {signal_price(signal)}</span>
              <span>Edge: {signal_edge(signal)}</span>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp signal_type(%{type: :auto_buy}), do: :auto_buy
  defp signal_type(_), do: :signal

  defp signal_station_code(%{station_code: code}), do: code
  defp signal_station_code(%WeatherEdge.Signals.Signal{station_code: code}), do: code
  defp signal_station_code(_), do: "???"

  defp signal_outcome(%{outcome_label: label}), do: label
  defp signal_outcome(%WeatherEdge.Signals.Signal{outcome_label: label}), do: label
  defp signal_outcome(_), do: "-"

  defp signal_price(%{market_price: price}) when is_float(price),
    do: :erlang.float_to_binary(price, decimals: 2)

  defp signal_price(%WeatherEdge.Signals.Signal{market_price: price}) when is_float(price),
    do: :erlang.float_to_binary(price, decimals: 2)

  defp signal_price(_), do: "-"

  defp signal_edge(%{edge: edge}) when is_float(edge) do
    sign = if edge >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(edge * 100, decimals: 1)}%"
  end

  defp signal_edge(%WeatherEdge.Signals.Signal{edge: edge}) when is_float(edge) do
    sign = if edge >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(edge * 100, decimals: 1)}%"
  end

  defp signal_edge(_), do: "-"

  defp signal_alert_level(%{alert_level: level}), do: level
  defp signal_alert_level(%WeatherEdge.Signals.Signal{alert_level: level}), do: level
  defp signal_alert_level(_), do: nil

  defp signal_alert_text(signal) do
    case signal_alert_level(signal) do
      "opportunity" -> "Opportunity"
      "strong" -> "Strong"
      "extreme" -> "Extreme"
      "safe_no" -> "Safe NO"
      _ ->
        if signal_type(signal) == :auto_buy, do: "Auto-Buy", else: "Signal"
    end
  end

  defp signal_border_class(signal) do
    case {signal_type(signal), signal_alert_level(signal)} do
      {:auto_buy, _} -> "border-indigo-300 bg-indigo-50"
      {_, "extreme"} -> "border-red-300 bg-red-50"
      {_, "strong"} -> "border-orange-300 bg-orange-50"
      {_, "opportunity"} -> "border-yellow-300 bg-yellow-50"
      {_, "safe_no"} -> "border-green-300 bg-green-50"
      _ -> "border-zinc-200 bg-zinc-50"
    end
  end

  defp signal_dot_class(signal) do
    case {signal_type(signal), signal_alert_level(signal)} do
      {:auto_buy, _} -> "bg-indigo-500"
      {_, "extreme"} -> "bg-red-500"
      {_, "strong"} -> "bg-orange-500"
      {_, "opportunity"} -> "bg-yellow-500"
      {_, "safe_no"} -> "bg-green-500"
      _ -> "bg-zinc-400"
    end
  end

  defp alert_badge_class(signal) do
    case {signal_type(signal), signal_alert_level(signal)} do
      {:auto_buy, _} -> "bg-indigo-100 text-indigo-700"
      {_, "extreme"} -> "bg-red-100 text-red-700"
      {_, "strong"} -> "bg-orange-100 text-orange-700"
      {_, "opportunity"} -> "bg-yellow-100 text-yellow-700"
      {_, "safe_no"} -> "bg-green-100 text-green-700"
      _ -> "bg-zinc-100 text-zinc-600"
    end
  end

  defp format_timestamp(%{computed_at: %DateTime{} = dt}) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_timestamp(%WeatherEdge.Signals.Signal{computed_at: %DateTime{} = dt}) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_timestamp(%{timestamp: %DateTime{} = dt}) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_timestamp(_), do: "--:--:--"
end
