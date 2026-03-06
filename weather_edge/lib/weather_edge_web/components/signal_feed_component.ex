defmodule WeatherEdgeWeb.Components.SignalFeedComponent do
  use Phoenix.Component

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
              <span class="font-semibold text-zinc-700">{get_field(signal, :station_code, "???")}</span>
              <span class="font-bold text-zinc-900">{extract_temp(signal)}</span>
            </div>
            <div class="flex items-center gap-2">
              <span class={["text-xs font-bold px-2 py-0.5 rounded", side_class(signal)]}>
                {side_text(signal)}
              </span>
              <span class={["text-xs font-medium px-2 py-0.5 rounded-full", alert_badge_class(signal)]}>
                {signal_alert_text(signal)}
              </span>
            </div>
          </div>

          <div class="mt-1 flex items-center gap-4 text-xs text-zinc-500">
            <%= if signal_type(signal) == :auto_buy do %>
              <span class="font-medium text-indigo-600">AUTO-BUY</span>
              <span>@ {format_price(signal)}</span>
            <% else %>
              <span>Market: {format_price(signal)}</span>
              <span>Model: {format_model_prob(signal)}</span>
              <span class="font-semibold text-zinc-700">Edge: {format_edge(signal)}</span>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Field access (handles both structs and maps) ---

  defp get_field(%WeatherEdge.Signals.Signal{} = s, field, default) do
    Map.get(s, field) || default
  end

  defp get_field(map, field, default) when is_map(map) do
    Map.get(map, field) || default
  end

  defp get_field(_, _, default), do: default

  # --- Extract temperature from outcome label ---

  defp extract_temp(signal) do
    label = get_field(signal, :outcome_label, "")

    cond do
      match = Regex.run(~r/(\-?\d+)\s*°?\s*([CF])\s+(or below|or higher)/i, label) ->
        [_, temp, unit, qualifier] = match
        "#{temp}°#{String.upcase(unit)} #{String.downcase(qualifier)}"

      match = Regex.run(~r/between\s+(\-?\d+)\s*-\s*(\-?\d+)\s*°?\s*([CF])/i, label) ->
        [_, low, high, unit] = match
        "#{low}-#{high}°#{String.upcase(unit)}"

      match = Regex.run(~r/(\-?\d+)\s*°\s*([CF])/, label) ->
        [_, temp, unit] = match
        "#{temp}°#{String.upcase(unit)}"

      true ->
        ""
    end
  end

  # --- Side (BUY YES / BUY NO) ---

  defp get_side(%WeatherEdge.Signals.Signal{recommended_side: side}), do: side
  defp get_side(%{recommended_side: side}), do: side
  defp get_side(_), do: nil

  defp side_text(signal) do
    case signal_type(signal) do
      :auto_buy -> "BOUGHT"
      _ ->
        case get_side(signal) do
          "YES" -> "BUY YES"
          "NO" -> "BUY NO"
          _ -> "-"
        end
    end
  end

  defp side_class(signal) do
    case signal_type(signal) do
      :auto_buy -> "bg-indigo-600 text-white"
      _ ->
        case get_side(signal) do
          "YES" -> "bg-green-600 text-white"
          "NO" -> "bg-red-600 text-white"
          _ -> "bg-zinc-200 text-zinc-600"
        end
    end
  end

  # --- Formatting ---

  defp format_price(signal) do
    price = get_field(signal, :market_price, nil)

    if is_number(price) do
      "$#{:erlang.float_to_binary(price / 1, decimals: 2)}"
    else
      "-"
    end
  end

  defp format_model_prob(signal) do
    prob = get_field(signal, :model_probability, nil)

    if is_number(prob) do
      "#{:erlang.float_to_binary(prob * 100, decimals: 1)}%"
    else
      "-"
    end
  end

  defp format_edge(signal) do
    edge = get_field(signal, :edge, nil)

    if is_number(edge) do
      sign = if edge >= 0, do: "+", else: ""
      "#{sign}#{:erlang.float_to_binary(edge * 100, decimals: 1)}%"
    else
      "-"
    end
  end

  defp format_timestamp(%{computed_at: %DateTime{} = dt}), do: Calendar.strftime(dt, "%H:%M:%S")

  defp format_timestamp(%WeatherEdge.Signals.Signal{computed_at: %DateTime{} = dt}),
    do: Calendar.strftime(dt, "%H:%M:%S")

  defp format_timestamp(%{timestamp: %DateTime{} = dt}), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_timestamp(_), do: "--:--:--"

  # --- Signal type & alert ---

  defp signal_type(%{type: :auto_buy}), do: :auto_buy
  defp signal_type(_), do: :signal

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

  # --- Styling ---

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
end
