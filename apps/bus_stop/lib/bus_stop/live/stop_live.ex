defmodule BusStop.StopLive do
  @moduledoc """
  Live departures board for a single stop.

  Shows departures from the loaded GTFS feed, adjusted by TransLink's
  realtime trip updates where available. The poller refreshes the board of
  every watched stop every 30s and broadcasts it through `Core.StopBoard`.

  The look comes from a `BusStop.StopBoard.Theme`, picked with `?theme=`
  (e.g. `/busstops/50001?theme=led`); unknown or missing values fall back
  to the configured default.
  """

  use BusStop, :live_view

  alias BusStop.StopBoard.{Theme, View}
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
  def handle_params(params, _uri, socket) do
    {key, module} = Theme.resolve(params["theme"])
    {:noreply, assign(socket, theme_key: key, theme: module)}
  end

  @impl true
  def handle_info({:stop_board, board}, socket) do
    {:noreply, assign_board(socket, board)}
  end

  defp assign_board(socket, board) do
    assign(socket, board: View.build(socket.assigns.stop_code, board))
  end

  @impl true
  def render(assigns), do: assigns.theme.render(assigns)
end
