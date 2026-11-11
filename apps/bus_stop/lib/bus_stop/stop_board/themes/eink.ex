defmodule BusStop.StopBoard.Themes.Eink do
  @moduledoc """
  For e-ink displays: pure black on paper white, no greys, no animation.
  """

  use BusStop.StopBoard.Theme, label: "E-ink"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#f4f1ea] text-black antialiased [font-feature-settings:'tnum']">
      <main class="mx-auto max-w-3xl px-4 py-6 sm:px-8 sm:py-10">
        <header class="flex items-start justify-between gap-4 border-b-4 border-black pb-4">
          <div class="min-w-0">
            <p class="text-sm font-bold uppercase tracking-[0.2em]">Stop {@board.stop_code}</p>
            <h1 class="mt-1 text-2xl font-black leading-tight sm:text-4xl">
              {if @board.found?, do: @board.stop_name, else: "Stop not found"}
            </h1>
          </div>
          <div class="shrink-0 text-right">
            <p class="text-3xl font-black leading-none sm:text-5xl">{@board.clock}</p>
            <p class="mt-1 text-xs font-bold uppercase tracking-widest">Next departures</p>
          </div>
        </header>

        <ol :if={@board.departures != []}>
          <li
            :for={departure <- @board.departures}
            class="flex items-center gap-4 border-b-2 border-black py-5 sm:gap-6"
          >
            <span class="flex h-14 w-16 shrink-0 items-center justify-center bg-black text-2xl font-black text-[#f4f1ea] sm:h-16 sm:w-20 sm:text-3xl">
              {departure.route}
            </span>
            <div class="min-w-0 flex-1">
              <p class="truncate text-xl font-bold sm:text-3xl">{departure.headsign}</p>
              <p class="mt-1 text-sm font-semibold uppercase tracking-wider sm:text-base">
                {departure.status}
              </p>
            </div>
            <div class="shrink-0 text-right">
              <p :if={departure.minutes == 0} class="text-3xl font-black leading-none sm:text-5xl">
                Due
              </p>
              <div :if={departure.minutes > 0}>
                <p class="text-3xl font-black leading-none sm:text-5xl">
                  <%!-- "~" marks a timetable time with no live prediction --%>
                  <span :if={!departure.realtime?} class="font-bold">~</span>{departure.minutes}
                </p>
                <p class="text-xs font-bold uppercase tracking-widest">min</p>
              </div>
            </div>
          </li>
        </ol>

        <p
          :if={@board.found? && @board.departures == []}
          class="border-b-2 border-black py-8 text-xl font-bold"
        >
          No departures in the next 2 hours.
        </p>

        <p :if={!@board.found?} class="border-b-2 border-black py-8 text-xl font-bold">
          No stop with code {@board.stop_code} in the current schedule.
        </p>

        <footer class="mt-4 flex justify-between text-xs font-semibold uppercase tracking-widest">
          <span>Updated {@board.updated_at}</span>
          <span>~ scheduled, not live · refreshes every 30s</span>
        </footer>
      </main>
    </div>
    """
  end
end
