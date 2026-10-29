defmodule Core.GTFS.Calendar do
  use Ecto.Schema

  @primary_key false

  schema "gtfs_calendar" do
    field :version, :date, primary_key: true
    field :service_id, :string, primary_key: true
    field :monday, :boolean
    field :tuesday, :boolean
    field :wednesday, :boolean
    field :thursday, :boolean
    field :friday, :boolean
    field :saturday, :boolean
    field :sunday, :boolean
    field :start_date, :date
    field :end_date, :date
  end
end
