defmodule Core.Repo.Migrations.CreateGtfsScheduleTables do
  use Ecto.Migration

  def change do
    create table(:gtfs_routes, primary_key: false) do
      add :route_id, :string, primary_key: true
      add :agency_id, :string
      add :route_short_name, :string
      add :route_long_name, :string
      add :route_type, :integer
      add :route_color, :string
      add :route_text_color, :string
    end

    create table(:gtfs_trips, primary_key: false) do
      add :trip_id, :string, primary_key: true
      add :route_id, :string, null: false
      add :service_id, :string, null: false
      add :trip_headsign, :string
      add :direction_id, :integer
      add :block_id, :string
      add :shape_id, :string
    end

    create index(:gtfs_trips, [:route_id])
    create index(:gtfs_trips, [:service_id])

    # arrival_time / departure_time are seconds after midnight of the service
    # day; GTFS allows values past 24:00:00 for trips running after midnight.
    create table(:gtfs_stop_times, primary_key: false) do
      add :trip_id, :string, primary_key: true
      add :stop_sequence, :integer, primary_key: true
      add :stop_id, :string, null: false
      add :arrival_time, :integer
      add :departure_time, :integer
      add :stop_headsign, :string
      add :pickup_type, :integer
      add :drop_off_type, :integer
    end

    create index(:gtfs_stop_times, [:stop_id, :departure_time])

    create table(:gtfs_calendar, primary_key: false) do
      add :service_id, :string, primary_key: true
      add :monday, :boolean, null: false
      add :tuesday, :boolean, null: false
      add :wednesday, :boolean, null: false
      add :thursday, :boolean, null: false
      add :friday, :boolean, null: false
      add :saturday, :boolean, null: false
      add :sunday, :boolean, null: false
      add :start_date, :date, null: false
      add :end_date, :date, null: false
    end

    create table(:gtfs_calendar_dates, primary_key: false) do
      add :service_id, :string, primary_key: true
      add :date, :date, primary_key: true
      add :exception_type, :integer, null: false
    end

    create index(:gtfs_calendar_dates, [:date])
  end
end
