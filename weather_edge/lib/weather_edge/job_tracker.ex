defmodule WeatherEdge.JobTracker do
  @moduledoc """
  Tracks last execution time for background workers via persistent_term.
  """

  def record(worker_key) do
    :persistent_term.put({:job_last_run, worker_key}, DateTime.utc_now())
  end

  def last_run(worker_key) do
    :persistent_term.get({:job_last_run, worker_key}, nil)
  end

  def time_ago(nil), do: "never"

  def time_ago(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end
