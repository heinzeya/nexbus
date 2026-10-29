defmodule Core.GTFS.Stop do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "gtfs_stops" do
    field :version, :date, primary_key: true
    field :stop_id, :string, primary_key: true
    field :stop_code, :string
    field :stop_name, :string
    field :latitude, :float
    field :longitude, :float
    field :location_type, :integer
  end

  def changeset(stop, attrs) do
    stop
    |> cast(attrs, [:version, :stop_id, :stop_code, :stop_name, :latitude, :longitude, :location_type])
    |> validate_required([:version, :stop_id])
  end
end
