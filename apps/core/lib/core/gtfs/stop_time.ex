defmodule Core.GTFS.StopTime do
  @moduledoc """
  A scheduled stop on a trip.

  `arrival_time` and `departure_time` are seconds after midnight of the
  service day, and can exceed 86_400 for trips that run past midnight.
  """

  use Ecto.Schema

  @primary_key false

  schema "gtfs_stop_times" do
    field :version, :date, primary_key: true
    field :trip_id, :string, primary_key: true
    field :stop_sequence, :integer, primary_key: true
    field :stop_id, :string
    field :arrival_time, :integer
    field :departure_time, :integer
    field :stop_headsign, :string
    field :pickup_type, :integer
    field :drop_off_type, :integer
  end
end
