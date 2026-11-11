defmodule BusStop.StopBoard.View do
  @moduledoc """
  Display-ready data for a stop board, shared by every theme.

  `build/3` turns a `Core.StopBoard` result into strings and numbers a
  template can print as-is. Each departure is a map with:

    * `:route` – sign label, leading zeros stripped ("23", "N19")
    * `:headsign` – destination without the repeated route number
    * `:minutes` – whole minutes until departure; `0` means due
    * `:realtime?` – whether the time is a live prediction
    * `:scheduled` / `:eta` – local "HH:MM" clock times
    * `:delay` – "on time", "3 min late", or nil when not realtime
    * `:status` – one-line summary, e.g. "Scheduled 09:52 · ETA 10:00 (8 min late)"
  """

  defstruct [:stop_code, :stop_name, :found?, :clock, :updated_at, departures: []]

  @type t :: %__MODULE__{}

  def build(stop_code, board, now \\ DateTime.utc_now())

  def build(stop_code, {:ok, board}, now) do
    %__MODULE__{
      stop_code: stop_code,
      stop_name: board.stop.stop_name,
      found?: true,
      clock: clock(board.generated_at),
      updated_at: board.generated_at |> local() |> Calendar.strftime("%H:%M:%S"),
      departures:
        board.departures
        |> Enum.sort_by(&{route_sort_key(&1.route), DateTime.to_unix(&1.departs_at)})
        |> Enum.map(&departure(&1, now))
    }
  end

  def build(stop_code, {:error, :stop_not_found}, now) do
    %__MODULE__{
      stop_code: stop_code,
      found?: false,
      clock: clock(now),
      updated_at: now |> local() |> Calendar.strftime("%H:%M:%S")
    }
  end

  defp departure(d, now) do
    delay = if d.realtime?, do: delay_label(d.delay)

    %{
      route: route_label(d.route),
      headsign: headsign(d),
      minutes: max(div(DateTime.diff(d.departs_at, now), 60), 0),
      realtime?: d.realtime?,
      scheduled: clock(d.scheduled_at),
      eta: clock(d.departs_at),
      delay: delay,
      status:
        if(d.realtime?,
          do: "Scheduled #{clock(d.scheduled_at)} · ETA #{clock(d.departs_at)} (#{delay})",
          else: "Scheduled #{clock(d.scheduled_at)}"
        )
    }
  end

  # TransLink pads route numbers ("023"); signs show "23".
  defp route_label(nil), do: ""
  defp route_label(route), do: String.trim_leading(route, "0")

  # Natural order: 9, 23, 99, 401, then lettered routes N9, N19, R4.
  defp route_sort_key(route) do
    [_, prefix, number, rest] = Regex.run(~r/^([A-Za-z]*)(\d*)(.*)$/, route_label(route))
    {prefix, if(number == "", do: 0, else: String.to_integer(number)), rest}
  end

  # TransLink headsigns repeat the route ("23 Pacific/To English Bay").
  defp headsign(%{route: route, headsign: headsign}) when is_binary(headsign) do
    String.replace_prefix(headsign, route_label(route) <> " ", "")
  end

  defp headsign(_departure), do: ""

  defp delay_label(delay) when abs(delay) < 60, do: "on time"
  defp delay_label(delay) when delay > 0, do: "#{div(delay, 60)} min late"
  defp delay_label(delay), do: "#{div(-delay, 60)} min early"

  defp clock(datetime), do: datetime |> local() |> Calendar.strftime("%H:%M")

  defp local(datetime), do: DateTime.shift_zone!(datetime, Core.GTFS.timezone())
end
