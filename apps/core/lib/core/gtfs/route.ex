defmodule Core.GTFS.Route do
  use Ecto.Schema

  @primary_key false

  schema "gtfs_routes" do
    field :version, :date, primary_key: true
    field :route_id, :string, primary_key: true
    field :agency_id, :string
    field :route_short_name, :string
    field :route_long_name, :string
    field :route_type, :integer
    field :route_color, :string
    field :route_text_color, :string
  end
end
