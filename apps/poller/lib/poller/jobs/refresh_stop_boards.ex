defmodule Poller.Jobs.RefreshStopBoards do
  @moduledoc """
  Fetches realtime trip updates, then rebuilds and broadcasts the departure
  board of every stop that someone is currently viewing. Scheduled in
  `config :poller, Poller.Scheduler`.
  """

  def run do
    case Core.StopBoard.watched_stops() do
      [] ->
        :ok

      stop_codes ->
        Poller.TripUpdates.fetch_and_store()
        Enum.each(stop_codes, &Core.StopBoard.refresh/1)
    end
  end
end
