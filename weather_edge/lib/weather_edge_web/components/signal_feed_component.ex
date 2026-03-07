defmodule WeatherEdgeWeb.Components.SignalFeedComponent do
  use Phoenix.Component

  attr :signals, :list, required: true
  attr :filter, :string, default: "all"
  attr :limit, :integer, default: 20

  def signal_feed(assigns) do
    filtered =
      case assigns.filter do
        "all" ->
          assigns.signals

        "confirmed" ->
          Enum.filter(assigns.signals, fn s -> get_confidence(s) == "confirmed" end)

        "forecast" ->
          Enum.filter(assigns.signals, fn s -> get_confidence(s) == "forecast" end)

        "auto_buy" ->
          Enum.filter(assigns.signals, fn s -> signal_type(s) == :auto_buy end)

        level ->
          Enum.filter(assigns.signals, fn s -> signal_alert_level(s) == level end)
      end

    total_filtered = length(filtered)
    visible = Enum.take(filtered, assigns.limit)
    has_more = total_filtered > assigns.limit

    assigns =
      assigns
      |> assign(:filtered_signals, visible)
      |> assign(:total_filtered, total_filtered)
      |> assign(:has_more, has_more)

    ~H"""
    <div class="rounded-lg border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 p-4">
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-zinc-700 dark:text-zinc-300">
          Signal Feed
          <span class="text-xs font-normal text-zinc-400 ml-1">
            (<%= length(@filtered_signals) %><%= if @has_more, do: " of #{@total_filtered}", else: "" %>)
          </span>
        </h3>
        <div class="flex items-center gap-1">
          <button
            :for={{value, label, _color} <- filter_options()}
            phx-click="filter_signals"
            phx-value-filter={value}
            class={[
              "text-xs px-2 py-1 rounded-full font-medium transition-colors",
              if(@filter == value, do: active_filter_class(value), else: "bg-zinc-100 dark:bg-zinc-800 text-zinc-500 dark:text-zinc-400 hover:bg-zinc-200 dark:hover:bg-zinc-700")
            ]}
          >
            {label}
          </button>
        </div>
      </div>

      <div :if={@filtered_signals == []} class="text-sm text-zinc-400">
        <%= if @filter == "all" do %>
          No signals yet. Mispricing signals will appear here in real-time.
        <% else %>
          No signals matching this filter.
        <% end %>
      </div>

      <div :if={@filtered_signals != []} class="space-y-2 max-h-[600px] overflow-y-auto">
        <div
          :for={signal <- @filtered_signals}
          class={[
            "rounded-md border px-3 py-2 text-sm",
            signal_border_class(signal)
          ]}
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class={["inline-block w-2 h-2 rounded-full", signal_dot_class(signal)]}></span>
              <span class="font-mono text-xs text-zinc-500 dark:text-zinc-400">
                {format_timestamp(signal)}
              </span>
              <span class="font-semibold text-zinc-700 dark:text-zinc-300">{get_field(signal, :station_code, "???")}</span>
              <span class="font-bold text-zinc-900 dark:text-zinc-100">{extract_temp(signal)}</span>
              <span class="text-xs text-zinc-400">{format_target_date(signal)}</span>
            </div>
            <div class="flex items-center gap-2">
              <span class={["text-xs font-bold px-2 py-0.5 rounded", side_class(signal)]}>
                {side_text(signal)}
              </span>
              <span class={["text-xs font-medium px-2 py-0.5 rounded-full", alert_badge_class(signal)]}>
                {signal_alert_text(signal)}
              </span>
              <span class={["text-xs px-1.5 py-0.5 rounded", confidence_class(signal)]}>
                {confidence_text(signal)}
              </span>
            </div>
          </div>

          <div class="mt-1 flex items-center gap-4 text-xs text-zinc-500 dark:text-zinc-400">
            <%= if signal_type(signal) == :auto_buy do %>
              <span class="font-medium text-indigo-600 dark:text-indigo-400">AUTO-BUY</span>
              <span>@ {format_price(signal)}</span>
            <% else %>
              <span>Market: {format_price(signal)}</span>
              <span>Model: {format_model_prob(signal)}</span>
              <span class="font-semibold text-zinc-700 dark:text-zinc-300">Edge: {format_edge(signal)}</span>
            <% end %>
            <a
              :if={market_url(signal) != nil}
              href={market_url(signal)}
              target="_blank"
              class="text-blue-500 hover:text-blue-700 dark:text-blue-400 dark:hover:text-blue-300 hover:underline ml-auto"
            >
              Open ↗
            </a>
          </div>
        </div>

        <button
          :if={@has_more}
          phx-click="load_more_signals"
          class="mt-3 w-full rounded-md border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 py-2 text-xs font-medium text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-700 transition-colors"
        >
          Show more (<%= @total_filtered - length(@filtered_signals) %> remaining)
        </button>
      </div>
    </div>
    """
  end

  # --- Filters ---

  defp filter_options do
    [
      {"all", "All", "zinc"},
      {"confirmed", "Confirmed", "emerald"},
      {"extreme", "Extreme", "red"},
      {"strong", "Strong", "orange"},
      {"opportunity", "Opportunity", "yellow"},
      {"safe_no", "Safe NO", "green"},
      {"auto_buy", "Auto-Buy", "indigo"}
    ]
  end

  defp active_filter_class("all"), do: "bg-zinc-700 text-white"
  defp active_filter_class("confirmed"), do: "bg-emerald-600 text-white"
  defp active_filter_class("extreme"), do: "bg-red-600 text-white"
  defp active_filter_class("strong"), do: "bg-orange-500 text-white"
  defp active_filter_class("opportunity"), do: "bg-yellow-500 text-white"
  defp active_filter_class("safe_no"), do: "bg-green-600 text-white"
  defp active_filter_class("auto_buy"), do: "bg-indigo-600 text-white"
  defp active_filter_class(_), do: "bg-zinc-700 text-white"

  # --- Confidence ---

  defp get_confidence(%WeatherEdge.Signals.Signal{confidence: c}), do: c
  defp get_confidence(%{confidence: c}), do: c
  defp get_confidence(_), do: nil

  defp confidence_text(signal) do
    case get_confidence(signal) do
      "confirmed" -> "Confirmed"
      "high" -> "High"
      "forecast" -> "Forecast"
      _ -> nil
    end
  end

  defp confidence_class(signal) do
    case get_confidence(signal) do
      "confirmed" -> "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-400 font-semibold"
      "high" -> "bg-sky-100 text-sky-700 dark:bg-sky-900/30 dark:text-sky-400"
      "forecast" -> "bg-zinc-100 text-zinc-500 dark:bg-zinc-800 dark:text-zinc-500"
      _ -> "bg-zinc-50 text-zinc-400 dark:bg-zinc-800 dark:text-zinc-500"
    end
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
          _ -> "bg-zinc-200 text-zinc-600 dark:bg-zinc-700 dark:text-zinc-400"
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

  # --- Market URL ---

  defp market_url(%{event_slug: slug}) when is_binary(slug) and slug != "" do
    "https://polymarket.com/event/#{slug}"
  end

  defp market_url(%WeatherEdge.Signals.Signal{market_cluster: %{event_slug: slug}})
       when is_binary(slug) and slug != "" do
    "https://polymarket.com/event/#{slug}"
  end

  defp market_url(_), do: nil

  # --- Target date ---

  defp format_target_date(signal) do
    case get_field(signal, :target_date, nil) do
      %Date{} = date -> date_label(date)
      _ -> extract_date_from_label(get_field(signal, :outcome_label, ""))
    end
  end

  defp date_label(date) do
    Calendar.strftime(date, "%b %d")
  end

  defp extract_date_from_label(label) do
    case Regex.run(~r/on ((?:January|February|March|April|May|June|July|August|September|October|November|December) \d+)/i, label) do
      [_, date_str] -> date_str
      _ -> ""
    end
  end

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
      {:auto_buy, _} -> "border-indigo-300 bg-indigo-50 dark:border-indigo-700 dark:bg-indigo-950/30"
      {_, "extreme"} -> "border-red-300 bg-red-50 dark:border-red-700 dark:bg-red-950/30"
      {_, "strong"} -> "border-orange-300 bg-orange-50 dark:border-orange-700 dark:bg-orange-950/30"
      {_, "opportunity"} -> "border-yellow-300 bg-yellow-50 dark:border-yellow-700 dark:bg-yellow-950/30"
      {_, "safe_no"} -> "border-green-300 bg-green-50 dark:border-green-700 dark:bg-green-950/30"
      _ -> "border-zinc-200 bg-zinc-50 dark:border-zinc-700 dark:bg-zinc-800"
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
      {:auto_buy, _} -> "bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400"
      {_, "extreme"} -> "bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400"
      {_, "strong"} -> "bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400"
      {_, "opportunity"} -> "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400"
      {_, "safe_no"} -> "bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400"
      _ -> "bg-zinc-100 text-zinc-600 dark:bg-zinc-800 dark:text-zinc-400"
    end
  end
end
