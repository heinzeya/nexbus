defmodule Poller.TripUpdates do
  @moduledoc """
  Fetches the TransLink GTFS-realtime trip updates feed and stores it with
  `Core.Realtime.put_trip_updates/1`.

  Needs `TRANSLINK_API_KEY` in the environment (see config/runtime.exs);
  without it realtime is skipped and boards show scheduled times only.
  """

  require Logger

  alias Poller.GTFSRealtime.FeedMessage

  @canceled 3
  @skipped 1

  def fetch_and_store do
    with {:ok, api_key} <- api_key(),
         {:ok, body} <- fetch(api_key) do
      trip_updates = body |> FeedMessage.decode() |> to_trip_updates()
      Core.Realtime.put_trip_updates(trip_updates)
      {:ok, map_size(trip_updates)}
    else
      {:error, reason} = error ->
        Logger.warning("GTFS-realtime trip updates unavailable: #{inspect(reason)}")
        error
    end
  end

  defp api_key do
    case Application.get_env(:poller, :translink_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :no_api_key}
    end
  end

  defp fetch(api_key) do
    url = Application.fetch_env!(:poller, :gtfs_realtime_url)

    case Req.get(url, params: [apikey: api_key], decode_body: false, receive_timeout: 20_000, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # %{trip_id => %{start_date, canceled?, stops: [%{stop_sequence, delay, time, skipped?}]}}
  defp to_trip_updates(%FeedMessage{entity: entities}) do
    for %{trip_update: %{trip: %{trip_id: trip_id} = trip} = update} <- entities,
        is_binary(trip_id),
        into: %{} do
      stops =
        for stu <- update.stop_time_update, stu.stop_sequence do
          event = stu.departure || stu.arrival

          %{
            stop_sequence: stu.stop_sequence,
            delay: event && event.delay,
            time: event && event.time,
            skipped?: stu.schedule_relationship == @skipped
          }
        end

      {trip_id,
       %{
         start_date: trip.start_date,
         canceled?: trip.schedule_relationship == @canceled,
         stops: Enum.sort_by(stops, & &1.stop_sequence)
       }}
    end
  end
end
