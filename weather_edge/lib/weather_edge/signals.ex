defmodule WeatherEdge.Signals do
  @moduledoc """
  Context module for managing Signal records.
  """

  import Ecto.Query
  alias WeatherEdge.Repo
  alias WeatherEdge.Signals.Signal

  @doc """
  Creates a Signal record.
  """
  @spec create_signal(map()) :: {:ok, Signal.t()} | {:error, Ecto.Changeset.t()}
  def create_signal(attrs) do
    %Signal{}
    |> Signal.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple Signal records from a list of detector results.
  """
  @spec store_signals(integer(), String.t(), [map()]) :: {:ok, [Signal.t()]}
  def store_signals(market_cluster_id, station_code, signals) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    results =
      Enum.map(signals, fn signal ->
        attrs = %{
          market_cluster_id: market_cluster_id,
          station_code: station_code,
          computed_at: now,
          outcome_label: signal.outcome_label,
          model_probability: signal.model_probability,
          market_price: signal.market_yes_price,
          edge: signal.edge,
          recommended_side: signal.recommended_side,
          alert_level: signal.alert_level
        }

        case create_signal(attrs) do
          {:ok, record} -> record
          {:error, _} -> nil
        end
      end)
      |> Enum.filter(& &1)

    {:ok, results}
  end

  @doc """
  Lists recent signals for a station.
  """
  @spec list_signals(String.t(), keyword()) :: [Signal.t()]
  def list_signals(station_code, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Signal
    |> where([s], s.station_code == ^station_code)
    |> order_by([s], desc: s.computed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists recent signals for a market cluster.
  """
  @spec list_signals_for_cluster(integer(), keyword()) :: [Signal.t()]
  def list_signals_for_cluster(cluster_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Signal
    |> where([s], s.market_cluster_id == ^cluster_id)
    |> order_by([s], desc: s.computed_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
