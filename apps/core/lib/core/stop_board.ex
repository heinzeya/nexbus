defmodule Core.StopBoard do
  @moduledoc """
  Departure boards for the stops people are currently viewing.

  A viewer calls `subscribe/1`, which registers the stop as watched and
  subscribes to its PubSub topic. The poller calls `refresh/1` for every
  `watched_stops/0`, which rebuilds the board, caches it and broadcasts
  `{:stop_board, board}` to the subscribers.

  A board is `{:ok, %{stop: stop, departures: list, generated_at: datetime}}`
  or `{:error, :stop_not_found}`.
  """

  alias Core.{Cache, GTFS, Realtime}

  @registry Core.StopBoard.Registry
  @cache_ttl :timer.minutes(2)
  @limit 6
  # Scheduled departures this far in the past are still fetched, so buses
  # running late appear once realtime delays are applied.
  @lookback 30 * 60

  def topic(stop_code), do: "stop_board:#{stop_code}"

  @doc "Watches `stop_code` from the calling process until it exits."
  def subscribe(stop_code) do
    {:ok, _} = Registry.register(@registry, stop_code, nil)
    Phoenix.PubSub.subscribe(Core.PubSub, topic(stop_code))
  end

  def watched_stops do
    @registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()
  end

  @doc "Returns the cached board for `stop_code`, building it on a miss."
  def fetch(stop_code) do
    case Cache.get!({__MODULE__, stop_code}) do
      nil -> build_and_cache(stop_code)
      board -> board
    end
  end

  @doc "Rebuilds the board for `stop_code` and broadcasts it to viewers."
  def refresh(stop_code) do
    board = build_and_cache(stop_code)
    Phoenix.PubSub.broadcast(Core.PubSub, topic(stop_code), {:stop_board, board})
    board
  end

  defp build_and_cache(stop_code) do
    now = DateTime.utc_now()

    board =
      with {:ok, result} <- GTFS.upcoming_departures(stop_code, now, limit: nil, lookback: @lookback) do
        departures =
          result.departures
          |> Realtime.apply_trip_updates(Realtime.trip_updates())
          |> Enum.filter(&(DateTime.compare(&1.departs_at, now) != :lt))
          |> Enum.sort_by(& &1.departs_at, DateTime)
          |> Enum.take(@limit)

        {:ok, %{stop: result.stop, departures: departures, generated_at: now}}
      end

    Cache.put({__MODULE__, stop_code}, board, ttl: @cache_ttl)
    board
  end
end
