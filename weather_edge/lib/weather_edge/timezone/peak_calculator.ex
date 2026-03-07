defmodule WeatherEdge.Timezone.PeakCalculator do
  @moduledoc """
  Calculates solar peak status for weather stations based on their longitude.
  Peak sun hours (when daily high temp occurs) are typically 12:00-15:00 local solar time.

  Returns peak status used to determine signal confidence:
  - `:post_peak` — peak sun hours have passed, observed high is reliable
  - `:near_peak` — within peak window, temp may still rise
  - `:pre_peak` — before peak, only forecast models available
  - `:night` — nighttime, no solar heating
  """

  @type peak_status :: :post_peak | :near_peak | :pre_peak | :night

  @doc """
  Returns the peak status and hours since/until peak for a station.

  Uses longitude to estimate the UTC offset (solar time, not political timezone).
  Every 15° of longitude = 1 hour offset from UTC.

  ## Examples

      iex> peak_status(174.7, ~U[2026-03-07 04:00:00Z])  # Wellington at 4pm local
      {:post_peak, 1}

      iex> peak_status(-43.1, ~U[2026-03-07 15:00:00Z])  # Maceió at noon local
      {:near_peak, 0}
  """
  @spec peak_status(float(), DateTime.t()) :: {peak_status(), integer()}
  def peak_status(longitude, utc_now \\ DateTime.utc_now()) when is_number(longitude) do
    # Solar time offset from longitude (15° = 1 hour)
    utc_offset_hours = longitude / 15.0
    local_hour = rem(utc_now.hour + round(utc_offset_hours) + 24, 24)

    cond do
      # 16:00-05:59 local — post peak / night (high is locked)
      local_hour >= 16 or local_hour < 6 ->
        hours_since = if local_hour >= 16, do: local_hour - 15, else: local_hour + 9
        {:post_peak, hours_since}

      # 12:00-15:59 local — peak window (temp may still rise)
      local_hour >= 12 ->
        {:near_peak, local_hour - 12}

      # 06:00-11:59 local — pre peak (forecast only)
      true ->
        hours_until = 12 - local_hour
        {:pre_peak, hours_until}
    end
  end

  @doc """
  Returns a confidence level based on peak status.
  - `:confirmed` — post_peak, observed data is the final answer
  - `:high` — near_peak, observation is close to final
  - `:forecast` — pre_peak, relying on weather models
  """
  @spec confidence(peak_status()) :: :confirmed | :high | :forecast
  def confidence(:post_peak), do: :confirmed
  def confidence(:near_peak), do: :high
  def confidence(:pre_peak), do: :forecast
  def confidence(:night), do: :confirmed

  @doc """
  Returns a human-readable label for the peak status.
  """
  @spec status_label(peak_status()) :: String.t()
  def status_label(:post_peak), do: "Post-Peak"
  def status_label(:near_peak), do: "Near Peak"
  def status_label(:pre_peak), do: "Pre-Peak"
  def status_label(:night), do: "Night"

  @doc """
  Returns the recommended scan interval in minutes for a given peak status.
  Post-peak and near-peak get more frequent scans.
  """
  @spec scan_interval(peak_status()) :: pos_integer()
  def scan_interval(:post_peak), do: 2
  def scan_interval(:near_peak), do: 3
  def scan_interval(:pre_peak), do: 10
  def scan_interval(:night), do: 15

  @doc """
  Returns the local solar hour (0-23) for a given longitude at the current UTC time.
  """
  @spec local_solar_hour(float(), DateTime.t()) :: integer()
  def local_solar_hour(longitude, utc_now \\ DateTime.utc_now()) do
    utc_offset_hours = longitude / 15.0
    rem(utc_now.hour + round(utc_offset_hours) + 24, 24)
  end
end
