defmodule WeatherEdgeWeb.Components.AddStationModalComponent do
  use Phoenix.Component

  import WeatherEdgeWeb.CoreComponents

  attr :show, :boolean, default: false
  attr :step, :atom, default: :input
  attr :code, :string, default: ""
  attr :loading, :boolean, default: false
  attr :error, :string, default: nil
  attr :station_info, :map, default: nil

  def add_station_modal(assigns) do
    ~H"""
    <.modal
      :if={@show}
      id="add-station-modal"
      show
      on_cancel={Phoenix.LiveView.JS.push("close_add_station_modal")}
    >
      <h2 class="text-lg font-semibold text-zinc-900 mb-6">Add Weather Station</h2>

      <div :if={@step == :input}>
        <form phx-submit="validate_station" class="space-y-4">
          <div>
            <label for="station-code" class="block text-sm font-medium text-zinc-700 mb-1">
              ICAO Station Code
            </label>
            <input
              type="text"
              id="station-code"
              name="code"
              value={@code}
              maxlength="4"
              placeholder="e.g. KJFK"
              phx-hook="UppercaseInput"
              class="block w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 placeholder-zinc-400 focus:border-zinc-500 focus:ring-1 focus:ring-zinc-500 uppercase"
              autocomplete="off"
            />
          </div>

          <p :if={@error} class="text-sm text-red-600"><%= @error %></p>

          <button
            type="submit"
            disabled={@loading}
            class="w-full rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
          >
            <svg :if={@loading} class="animate-spin h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <%= if @loading, do: "Validating...", else: "Validate Station" %>
          </button>
        </form>
      </div>

      <div :if={@step == :confirm && @station_info}>
        <div class="rounded-lg border border-green-200 bg-green-50 p-4 mb-6">
          <h3 class="text-sm font-semibold text-green-800 mb-2">Station Found</h3>
          <dl class="space-y-1 text-sm text-green-700">
            <div class="flex justify-between">
              <dt class="font-medium">Code:</dt>
              <dd><%= @station_info.code %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="font-medium">City:</dt>
              <dd><%= @station_info.city %></dd>
            </div>
            <div :if={@station_info[:country]} class="flex justify-between">
              <dt class="font-medium">Country:</dt>
              <dd><%= @station_info.country %></dd>
            </div>
            <div class="flex justify-between">
              <dt class="font-medium">Coordinates:</dt>
              <dd><%= @station_info.latitude %>, <%= @station_info.longitude %></dd>
            </div>
          </dl>
        </div>

        <div class="flex gap-3">
          <button
            phx-click="confirm_add_station"
            class="flex-1 rounded-lg bg-zinc-900 px-4 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
          >
            Confirm & Add
          </button>
          <button
            phx-click="reset_add_station"
            class="flex-1 rounded-lg border border-zinc-300 px-4 py-2 text-sm font-semibold text-zinc-700 hover:bg-zinc-50"
          >
            Try Another
          </button>
        </div>
      </div>
    </.modal>
    """
  end
end
