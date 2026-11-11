defmodule BusStop.StopBoard.Themes.Led do
  @moduledoc """
  An amber-on-black, monospaced board in the style of an LED shelter sign.
  Suited to backlit screens viewed from a distance.
  """

  use BusStop.StopBoard.Theme, label: "LED sign"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-black font-mono text-[#ffb000] antialiased [font-feature-settings:'tnum']">
      <main class="mx-auto max-w-4xl px-4 py-6 sm:px-8 sm:py-10">
        <header class="flex items-baseline justify-between gap-4 pb-4 uppercase">
          <h1 class="min-w-0 truncate text-xl font-bold tracking-wider sm:text-3xl">
            {if @board.found?, do: @board.stop_name, else: "Stop #{@board.stop_code} not found"}
          </h1>
          <p class="shrink-0 text-2xl font-bold sm:text-4xl">{@board.clock}</p>
        </header>

        <div class="border-y border-[#ffb000]/40">
          <div
            :for={departure <- @board.departures}
            class="grid grid-cols-[4.5rem_1fr_auto] items-center gap-4 border-b border-[#ffb000]/15 py-3 uppercase last:border-b-0 sm:grid-cols-[6rem_1fr_auto] sm:py-4"
          >
            <span class="text-2xl font-bold sm:text-4xl">{departure.route}</span>
            <span class="truncate text-lg sm:text-2xl">{departure.headsign}</span>
            <span class="text-right text-2xl font-bold sm:text-4xl">
              <span :if={departure.minutes == 0} class="animate-pulse">Due</span>
              <span :if={departure.minutes > 0}>
                {departure.minutes}<span class="text-base sm:text-xl">{if departure.realtime?, do: "m", else: "m*"}</span>
              </span>
            </span>
          </div>

          <p :if={@board.found? && @board.departures == []} class="py-8 text-lg uppercase sm:text-2xl">
            No departures in the next 2 hours
          </p>
          <p :if={!@board.found?} class="py-8 text-lg uppercase sm:text-2xl">
            Not in the current schedule
          </p>
        </div>

        <footer class="mt-3 flex justify-between text-xs uppercase tracking-widest text-[#ffb000]/60">
          <span>Stop {@board.stop_code} · upd {@board.updated_at}</span>
          <span>* scheduled</span>
        </footer>
      </main>
    </div>
    """
  end
end
