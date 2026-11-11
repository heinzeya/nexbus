defmodule BusStop.StopBoard.Themes.Transit do
  @moduledoc """
  A light, colourful board with a coloured badge per route and live-status
  pills. Suited to phones and full-colour displays.
  """

  use BusStop.StopBoard.Theme, label: "Transit"

  # Full class strings so Tailwind's scanner picks them up.
  @badges ~w(
    bg-sky-600 bg-emerald-600 bg-amber-500 bg-rose-600
    bg-violet-600 bg-teal-600 bg-orange-600 bg-indigo-600
  )

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-100 text-slate-900 antialiased [font-feature-settings:'tnum']">
      <main class="mx-auto max-w-2xl px-4 py-6 sm:py-10">
        <header class="flex items-end justify-between gap-4 pb-5">
          <div class="min-w-0">
            <p class="text-sm font-medium text-slate-500">Stop {@board.stop_code}</p>
            <h1 class="mt-0.5 text-2xl font-semibold leading-tight sm:text-3xl">
              {if @board.found?, do: @board.stop_name, else: "Stop not found"}
            </h1>
          </div>
          <p class="shrink-0 text-2xl font-semibold text-slate-500 sm:text-3xl">{@board.clock}</p>
        </header>

        <ul :if={@board.departures != []} class="space-y-2">
          <li
            :for={departure <- @board.departures}
            class="flex items-center gap-4 rounded-xl bg-white p-4 shadow-sm"
          >
            <span class={[
              "flex h-12 min-w-14 shrink-0 items-center justify-center rounded-lg px-2 text-xl font-bold text-white",
              badge(departure.route)
            ]}>
              {departure.route}
            </span>
            <div class="min-w-0 flex-1">
              <p class="truncate text-lg font-semibold">{departure.headsign}</p>
              <p class="mt-1 flex flex-wrap items-center gap-2 text-sm text-slate-500">
                <span :if={departure.realtime?} class={[
                  "rounded-full px-2 py-0.5 text-xs font-medium",
                  departure.delay == "on time" && "bg-emerald-100 text-emerald-800",
                  departure.delay != "on time" && "bg-amber-100 text-amber-800"
                ]}>
                  {departure.delay}
                </span>
                <span :if={!departure.realtime?} class="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium">
                  Scheduled
                </span>
                <span>{departure.eta}</span>
              </p>
            </div>
            <div class="shrink-0 text-right">
              <p :if={departure.minutes == 0} class="text-2xl font-bold text-emerald-700">Now</p>
              <p :if={departure.minutes > 0} class="text-2xl font-bold">
                {departure.minutes}<span class="ml-0.5 text-sm font-medium text-slate-500">min</span>
              </p>
            </div>
          </li>
        </ul>

        <p :if={@board.found? && @board.departures == []} class="rounded-xl bg-white p-6 text-slate-600">
          No departures in the next 2 hours.
        </p>
        <p :if={!@board.found?} class="rounded-xl bg-white p-6 text-slate-600">
          No stop with code {@board.stop_code} in the current schedule.
        </p>

        <footer class="mt-4 text-center text-xs text-slate-500">
          Updated {@board.updated_at} · refreshes every 30s
        </footer>
      </main>
    </div>
    """
  end

  # Same route, same colour, on every board.
  defp badge(route), do: Enum.at(@badges, :erlang.phash2(route, length(@badges)))
end
