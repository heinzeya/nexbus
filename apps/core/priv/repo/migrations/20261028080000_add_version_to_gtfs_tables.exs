defmodule Core.Repo.Migrations.AddVersionToGtfsTables do
  use Ecto.Migration

  # {table, primary key columns without version}
  @tables [
    {"gtfs_stops", ["stop_id"]},
    {"gtfs_routes", ["route_id"]},
    {"gtfs_trips", ["trip_id"]},
    {"gtfs_stop_times", ["trip_id", "stop_sequence"]},
    {"gtfs_calendar", ["service_id"]},
    {"gtfs_calendar_dates", ["service_id", "date"]}
  ]

  # Existing rows have no version, so they are removed; reload the feed
  # with Datahub.GTFS.load_gtfs_file/2 afterwards.
  def up do
    for {table, keys} <- @tables do
      execute "TRUNCATE #{table}"

      alter table(table) do
        add :version, :date, null: false
      end

      execute "ALTER TABLE #{table} DROP CONSTRAINT #{table}_pkey"
      execute "ALTER TABLE #{table} ADD PRIMARY KEY (#{Enum.join(["version" | keys], ", ")})"
    end

    drop index(:gtfs_stops, [:stop_code])
    drop index(:gtfs_trips, [:route_id])
    drop index(:gtfs_trips, [:service_id])
    drop index(:gtfs_stop_times, [:stop_id, :departure_time])
    drop index(:gtfs_calendar_dates, [:date])

    create index(:gtfs_stops, [:version, :stop_code])
    create index(:gtfs_trips, [:version, :route_id])
    create index(:gtfs_trips, [:version, :service_id])
    create index(:gtfs_stop_times, [:version, :stop_id, :departure_time])
    create index(:gtfs_calendar_dates, [:version, :date])
  end

  def down do
    drop index(:gtfs_stops, [:version, :stop_code])
    drop index(:gtfs_trips, [:version, :route_id])
    drop index(:gtfs_trips, [:version, :service_id])
    drop index(:gtfs_stop_times, [:version, :stop_id, :departure_time])
    drop index(:gtfs_calendar_dates, [:version, :date])

    for {table, keys} <- @tables do
      execute "TRUNCATE #{table}"
      execute "ALTER TABLE #{table} DROP CONSTRAINT #{table}_pkey"

      alter table(table) do
        remove :version
      end

      execute "ALTER TABLE #{table} ADD PRIMARY KEY (#{Enum.join(keys, ", ")})"
    end

    create index(:gtfs_stops, [:stop_code])
    create index(:gtfs_trips, [:route_id])
    create index(:gtfs_trips, [:service_id])
    create index(:gtfs_stop_times, [:stop_id, :departure_time])
    create index(:gtfs_calendar_dates, [:date])
  end
end
