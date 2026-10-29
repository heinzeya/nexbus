defmodule Core.Realtime do
  @moduledoc """
  Realtime trip updates (from `Poller.TripUpdates`) and how they adjust
  scheduled departures.

  Trip updates are a map of `trip_id => %{start_date, canceled?, stops}`,
  where `stops` is sorted by `stop_sequence` and each has `:delay` (seconds)
  and/or `:time` (unix seconds) and `:skipped?`.
  """

  alias Core.Cache

  @cache_key {__MODULE__, :trip_updates}
  @cache_ttl :timer.minutes(3)

  def put_trip_updates(trip_updates), do: Cache.put(@cache_key, trip_updates, ttl: @cache_ttl)

  def trip_updates, do: Cache.get!(@cache_key, %{})

  @doc """
  Applies `trip_updates` to scheduled departures (as returned by
  `Core.GTFS.upcoming_departures/3`).

  Each departure gets `:realtime?`, `:delay` (seconds, `nil` without
  realtime), `:scheduled_at` (the timetable time) and `:departs_at` (the
  predicted time, or the timetable time without realtime). Cancelled trips
  and skipped stops are removed. Following the GTFS-realtime spec, a stop
  without its own update takes the delay of the nearest earlier updated
  stop on the trip.
  """
  def apply_trip_updates(departures, trip_updates) do
    Enum.flat_map(departures, fn departure ->
      case matching_update(trip_updates, departure) do
        nil -> [scheduled(departure)]
        %{canceled?: true} -> []
        update -> adjust(departure, update)
      end
    end)
  end

  defp matching_update(trip_updates, departure) do
    service_date = Calendar.strftime(departure.service_date, "%Y%m%d")

    case Map.get(trip_updates, departure.trip_id) do
      %{start_date: start_date} = update when start_date in [nil, service_date] -> update
      _ -> nil
    end
  end

  defp adjust(departure, update) do
    stop = Enum.find(update.stops, &(&1.stop_sequence == departure.stop_sequence))
    earlier = update.stops |> Enum.filter(&(&1.stop_sequence < departure.stop_sequence)) |> List.last()

    cond do
      stop && stop.skipped? ->
        []

      stop && stop.time ->
        departs_at = DateTime.from_unix!(stop.time)
        [realtime(departure, departs_at, DateTime.diff(departs_at, departure.departs_at))]

      delay = (stop && stop.delay) || (earlier && earlier.delay) ->
        [realtime(departure, DateTime.add(departure.departs_at, delay), delay)]

      true ->
        [scheduled(departure)]
    end
  end

  defp scheduled(departure) do
    Map.merge(departure, %{scheduled_at: departure.departs_at, realtime?: false, delay: nil})
  end

  defp realtime(departure, departs_at, delay) do
    Map.merge(departure, %{
      scheduled_at: departure.departs_at,
      departs_at: departs_at,
      delay: delay,
      realtime?: true
    })
  end
end
