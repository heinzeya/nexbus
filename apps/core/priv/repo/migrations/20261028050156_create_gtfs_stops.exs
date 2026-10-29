defmodule Core.Repo.Migrations.CreateGtfsStops do
  use Ecto.Migration

  def change do
    create table(:gtfs_stops, primary_key: false) do
      add :stop_id, :string, primary_key: true
      add :stop_code, :string
      add :stop_name, :string
      add :latitude, :float
      add :longitude, :float
      add :location_type, :integer
    end

    create index(:gtfs_stops, [:stop_code])
  end
end
