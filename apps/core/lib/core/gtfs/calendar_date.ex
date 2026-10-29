defmodule Core.GTFS.CalendarDate do
  @moduledoc """
  A one-off service change. `exception_type` 1 adds service on `date`,
  2 removes it.
  """

  use Ecto.Schema

  @primary_key false

  schema "gtfs_calendar_dates" do
    field :version, :date, primary_key: true
    field :service_id, :string, primary_key: true
    field :date, :date, primary_key: true
    field :exception_type, :integer
  end
end
