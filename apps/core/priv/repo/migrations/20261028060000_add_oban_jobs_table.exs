defmodule Core.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migration.up()

  # Drops all Oban tables, including any queued jobs.
  def down, do: Oban.Migration.down(version: 1)
end
