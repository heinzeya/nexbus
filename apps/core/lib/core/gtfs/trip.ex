defmodule Core.GTFS.Trip do
  use Ecto.Schema

  @primary_key false

  schema "gtfs_trips" do
    field :version, :date, primary_key: true
    field :trip_id, :string, primary_key: true
    field :route_id, :string
    field :service_id, :string
    field :trip_headsign, :string
    field :direction_id, :integer
    field :block_id, :string
    field :shape_id, :string
  end
end
