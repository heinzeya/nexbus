defmodule Core.GTFS do
  @moduledoc """
  Queries over the GTFS schedule loaded by `Datahub.GTFS`.

  Times in `gtfs_stop_times` are seconds from the start of a service day,
  which GTFS defines as noon minus 12 hours in the feed's timezone.
  """

  import Ecto.Query

  alias Core.Repo
  alias Core.GTFS.{Calendar, CalendarDate, Route, Stop, StopTime, Trip}

  @weekdays ~w(monday tuesday wednesday thursday friday saturday sunday)a

  def timezone, do: Application.fetch_env!(:core, :gtfs_timezone)

  @doc """
  The version to use on `date`: the latest one published on or before it,
  or the earliest stored version if all of them are newer.
  """
  def version_for(date) do
    Repo.one(from c in Calendar, where: c.version <= ^date, select: max(c.version)) ||
      Repo.one(from c in Calendar, select: min(c.version))
  end

  def get_stop_by_code(version, stop_code) do
    Repo.one(from s in Stop, where: s.version == ^version and s.stop_code == ^stop_code, limit: 1)
  end

  @doc "Service ids running on `date`, after applying calendar_dates exceptions."
  def active_service_ids(version, date) do
    weekday = Enum.at(@weekdays, Date.day_of_week(date) - 1)

    regular =
      Repo.all(
        from c in Calendar,
          where:
            c.version == ^version and c.start_date <= ^date and c.end_date >= ^date and
              field(c, ^weekday) == true,
          select: c.service_id
      )

    exceptions =
      Repo.all(
        from cd in CalendarDate,
          where: cd.version == ^version and cd.date == ^date,
          select: {cd.service_id, cd.exception_type}
      )

    added = for {service_id, 1} <- exceptions, do: service_id
    removed = for {service_id, 2} <- exceptions, do: service_id

    Enum.uniq(regular ++ added) -- removed
  end

  @doc """
  Next scheduled departures from the stop with `stop_code`, starting at `now`.

  Includes trips from the previous service day that are still running after
  midnight. Each departure has `:route`, `:headsign`, `:trip_id`,
  `:stop_sequence`, `:service_date` and `:departs_at` (a UTC `DateTime`).

  Options:
    * `:limit` - maximum departures returned, or `nil` for all (default 6)
    * `:window` - how far ahead to look, in seconds (default 2 hours)
    * `:lookback` - also include departures scheduled up to this many
      seconds before `now`, e.g. to catch late buses (default 0)

  Returns `{:ok, %{stop: stop, version: date, departures: list}}` or
  `{:error, :stop_not_found}`.
  """
  def upcoming_departures(stop_code, now \\ DateTime.utc_now(), opts \\ []) do
    limit = Keyword.get(opts, :limit, 6)
    window = Keyword.get(opts, :window, 2 * 3600)
    lookback = Keyword.get(opts, :lookback, 0)
    today = now |> DateTime.shift_zone!(timezone()) |> DateTime.to_date()
    version = version_for(today)

    case version && get_stop_by_code(version, stop_code) do
      %Stop{} = stop ->
        departures =
          [Date.add(today, -1), today]
          |> Enum.flat_map(fn service_date ->
            day_start = service_day_start(service_date)
            now_secs = DateTime.diff(now, day_start)
            service_ids = active_service_ids(version, service_date)

            version
            |> scheduled_departures(stop.stop_id, service_ids, now_secs - lookback, now_secs + window)
            |> Enum.map(fn departure ->
              Map.merge(departure, %{
                service_date: service_date,
                departs_at: DateTime.add(day_start, departure.departure_time)
              })
            end)
          end)
          |> Enum.sort_by(& &1.departs_at, DateTime)
          |> then(&if(limit, do: Enum.take(&1, limit), else: &1))

        {:ok, %{stop: stop, version: version, departures: departures}}

      _ ->
        {:error, :stop_not_found}
    end
  end

  defp scheduled_departures(_version, _stop_id, [], _from_secs, _to_secs), do: []

  defp scheduled_departures(version, stop_id, service_ids, from_secs, to_secs) do
    Repo.all(
      from st in StopTime,
        join: t in Trip,
        on: t.version == st.version and t.trip_id == st.trip_id,
        join: r in Route,
        on: r.version == t.version and r.route_id == t.route_id,
        where:
          st.version == ^version and st.stop_id == ^stop_id and t.service_id in ^service_ids and
            st.departure_time >= ^from_secs and st.departure_time < ^to_secs and
            coalesce(st.pickup_type, 0) != 1,
        order_by: st.departure_time,
        select: %{
          route: r.route_short_name,
          headsign: coalesce(st.stop_headsign, t.trip_headsign),
          trip_id: t.trip_id,
          stop_sequence: st.stop_sequence,
          departure_time: st.departure_time
        }
    )
  end

  # Noon minus 12h, so service days stay 24h of clock time across DST changes.
  defp service_day_start(date) do
    date
    |> DateTime.new!(~T[12:00:00], timezone())
    |> DateTime.add(-12 * 3600)
    |> DateTime.shift_zone!("Etc/UTC")
  end
end
