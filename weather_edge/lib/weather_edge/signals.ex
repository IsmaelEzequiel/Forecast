defmodule WeatherEdge.Signals do
  @moduledoc """
  Context module for managing Signal records.
  """

  import Ecto.Query
  alias WeatherEdge.Repo
  alias WeatherEdge.Signals.Signal
  alias WeatherEdge.PubSubHelper

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
  Deduplicates: skips signals for the same outcome + cluster within the last hour.
  """
  @spec store_signals(integer(), String.t(), [map()]) :: {:ok, [Signal.t()]}
  def store_signals(market_cluster_id, station_code, signals) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    one_hour_ago = DateTime.add(now, -3600, :second)

    recent_keys = recent_signal_keys(market_cluster_id, one_hour_ago)

    results =
      signals
      |> Enum.reject(fn signal ->
        key = {signal.outcome_label, signal.recommended_side}
        MapSet.member?(recent_keys, key)
      end)
      |> Enum.map(fn signal ->
        attrs = %{
          market_cluster_id: market_cluster_id,
          station_code: station_code,
          computed_at: now,
          outcome_label: signal.outcome_label,
          model_probability: signal.model_probability,
          market_price: signal.market_yes_price,
          edge: signal.edge,
          recommended_side: signal.recommended_side,
          alert_level: signal.alert_level,
          confidence: Map.get(signal, :confidence)
        }

        case create_signal(attrs) do
          {:ok, record} -> record
          {:error, _} -> nil
        end
      end)
      |> Enum.filter(& &1)

    Enum.each(results, fn signal ->
      PubSubHelper.broadcast(PubSubHelper.signals_new(), {:new_signal, signal})
    end)

    {:ok, results}
  end

  defp recent_signal_keys(market_cluster_id, since) do
    Signal
    |> where([s], s.market_cluster_id == ^market_cluster_id and s.computed_at >= ^since)
    |> select([s], {s.outcome_label, s.recommended_side})
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Lists recent signals across all stations.
  """
  @spec list_recent(keyword()) :: [Signal.t()]
  def list_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Signal
    |> order_by([s], desc: s.computed_at)
    |> limit(^limit)
    |> Repo.all()
    |> Repo.preload(:market_cluster)
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
