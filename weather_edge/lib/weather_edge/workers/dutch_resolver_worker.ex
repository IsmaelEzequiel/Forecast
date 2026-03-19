defmodule WeatherEdge.Workers.DutchResolverWorker do
  @moduledoc """
  Runs daily. Resolves dutch groups where target_date has passed
  and the market cluster has been resolved.
  """

  use Oban.Worker, queue: :cleanup

  require Logger

  alias WeatherEdge.Trading.DutchGroups
  alias WeatherEdge.Markets
  alias WeatherEdge.PubSubHelper

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    WeatherEdge.JobTracker.start(:dutch_resolver)
    groups = DutchGroups.list_open_with_orders()

    groups
    |> Enum.filter(fn g -> Date.compare(g.target_date, Date.utc_today()) in [:lt, :eq] end)
    |> Enum.each(&resolve_group/1)

    WeatherEdge.JobTracker.finish(:dutch_resolver)
    :ok
  end

  defp resolve_group(group) do
    cluster = Markets.get_cluster(group.market_cluster_id)

    cond do
      is_nil(cluster) ->
        Logger.warning("DutchResolver: Cluster #{group.market_cluster_id} not found for group #{group.id}")

      not cluster.resolved ->
        Logger.debug("DutchResolver: Cluster #{group.market_cluster_id} not yet resolved")

      true ->
        winning = find_winning_outcome(cluster)
        covered_labels = Enum.map(group.dutch_orders, & &1.outcome_label)
        won = winning != nil and winning in covered_labels

        actual_pnl =
          if won do
            group.guaranteed_payout - group.total_invested
          else
            -group.total_invested
          end

        DutchGroups.update_group(group, %{
          status: if(won, do: "won", else: "lost"),
          winning_outcome: winning,
          actual_pnl: actual_pnl,
          closed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

        Logger.info(
          "DutchResolver: #{group.station_code} #{group.target_date} — #{if won, do: "WON", else: "LOST"} (#{winning || "unknown"}) P&L: $#{Float.round(actual_pnl, 2)}"
        )

        PubSubHelper.broadcast(
          "dutch:resolved",
          {:dutch_resolved, group.id, %{status: if(won, do: "won", else: "lost"), winning_outcome: winning, actual_pnl: actual_pnl}}
        )
    end
  end

  defp find_winning_outcome(cluster) do
    case cluster.outcomes do
      outcomes when is_list(outcomes) ->
        # The winning outcome is the one with yes_price >= 0.95 (effectively resolved to YES)
        case Enum.find(outcomes, fn o -> (o["yes_price"] || 0) >= 0.95 end) do
          %{"outcome_label" => label} -> label
          %{"label" => label} -> label
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
