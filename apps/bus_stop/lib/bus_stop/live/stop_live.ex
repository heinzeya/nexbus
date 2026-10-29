defmodule BusStop.StopLive do
  @moduledoc """
  Live departures board for a single stop, styled for e-ink displays:
  pure black on paper white, no greys, no animation.

  Shows departures from the loaded GTFS feed, adjusted by TransLink's
  realtime trip updates where available. The poller refreshes the board of
  every watched stop every 30s and broadcasts it through `Core.StopBoard`.
  """

  use BusStop, :live_view

  alias Core.StopBoard

  @impl true
  def mount(%{"stop_code" => stop_code}, _session, socket) do
    if connected?(socket), do: StopBoard.subscribe(stop_code)

    {:ok,
     socket
     |> assign(stop_code: stop_code, page_title: "Stop #{stop_code}")
     |> assign_board(StopBoard.fetch(stop_code))}
  end

  @impl true
  def handle_info({:stop_board, board}, socket) do
    {:noreply, assign_board(socket, board)}
  end

  defp assign_board(socket, {:ok, board}) do
    assign(socket,
      stop: board.stop,
      departures:
        Enum.sort_by(board.departures, &{route_sort_key(&1.route), DateTime.to_unix(&1.departs_at)}),
      updated_at: local(board.generated_at),
      now: DateTime.utc_now()
    )
  end

  defp assign_board(socket, {:error, :stop_not_found}) do
    assign(socket, stop: nil, departures: [], updated_at: local(DateTime.utc_now()), now: DateTime.utc_now())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f4f1ea] text-black antialiased [font-feature-settings:'tnum']">
      <main class="mx-auto max-w-3xl px-4 py-6 sm:px-8 sm:py-10">
        <header class="flex items-start justify-between gap-4 border-b-4 border-black pb-4">
          <div class="min-w-0">
            <p class="text-sm font-bold uppercase tracking-[0.2em]">Stop {@stop_code}</p>
            <h1 class="mt-1 text-2xl font-black leading-tight sm:text-4xl">
              {if @stop, do: @stop.stop_name, else: "Stop not found"}
            </h1>
          </div>
          <div class="shrink-0 text-right">
            <p class="text-3xl font-black leading-none sm:text-5xl">{Calendar.strftime(@updated_at, "%H:%M")}</p>
            <p class="mt-1 text-xs font-bold uppercase tracking-widest">Next departures</p>
          </div>
        </header>

        <ol :if={@departures != []}>
          <li
            :for={departure <- @departures}
            class="flex items-center gap-4 border-b-2 border-black py-5 sm:gap-6"
          >
            <span class="flex h-14 w-16 shrink-0 items-center justify-center bg-black text-2xl font-black text-[#f4f1ea] sm:h-16 sm:w-20 sm:text-3xl">
              {route_label(departure.route)}
            </span>
            <div class="min-w-0 flex-1">
              <p class="truncate text-xl font-bold sm:text-3xl">{headsign(departure)}</p>
              <p class="mt-1 text-sm font-semibold uppercase tracking-wider sm:text-base">
                {status_label(departure)}
              </p>
            </div>
            <div class="shrink-0 text-right">
              <%= case minutes_until(departure.departs_at, @now) do %>
                <% 0 -> %>
                  <p class="text-3xl font-black leading-none sm:text-5xl">Due</p>
                <% minutes -> %>
                  <p class="text-3xl font-black leading-none sm:text-5xl">
                    <%!-- "~" marks a timetable time with no live prediction --%>
                    <span :if={!departure.realtime?} class="font-bold">~</span>{minutes}
                  </p>
                  <p class="text-xs font-bold uppercase tracking-widest">min</p>
              <% end %>
            </div>
          </li>
        </ol>

        <p :if={@stop && @departures == []} class="border-b-2 border-black py-8 text-xl font-bold">
          No departures in the next 2 hours.
        </p>

        <p :if={!@stop} class="border-b-2 border-black py-8 text-xl font-bold">
          No stop with code {@stop_code} in the current schedule.
        </p>

        <footer class="mt-4 flex justify-between text-xs font-semibold uppercase tracking-widest">
          <span>Updated {Calendar.strftime(@updated_at, "%H:%M:%S")}</span>
          <span>~ scheduled, not live · refreshes every 30s</span>
        </footer>
      </main>
    </div>
    """
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

  # "Scheduled 09:52 · ETA 10:00 (8 min late)"
  defp status_label(%{realtime?: true} = departure) do
    "Scheduled #{clock(departure.scheduled_at)} · ETA #{clock(departure.departs_at)} (#{delay_label(departure.delay)})"
  end

  defp status_label(departure), do: "Scheduled #{clock(departure.scheduled_at)}"

  defp delay_label(delay) when abs(delay) < 60, do: "on time"
  defp delay_label(delay) when delay > 0, do: "#{div(delay, 60)} min late"
  defp delay_label(delay), do: "#{div(-delay, 60)} min early"

  defp clock(datetime), do: datetime |> local() |> Calendar.strftime("%H:%M")

  defp minutes_until(departs_at, now), do: max(div(DateTime.diff(departs_at, now), 60), 0)

  defp local(datetime), do: DateTime.shift_zone!(datetime, Core.GTFS.timezone())
end
