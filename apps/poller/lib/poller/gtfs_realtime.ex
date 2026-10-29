# Subset of the GTFS-realtime protobuf schema needed to decode trip updates.
# Field numbers follow https://gtfs.org/realtime/proto/; fields not declared
# here (vehicle positions, alerts, extensions) are skipped when decoding.
# Enum fields are declared as int32, which has the same wire encoding.

defmodule Poller.GTFSRealtime.FeedMessage do
  use Protobuf, syntax: :proto2

  field :header, 1, required: true, type: Poller.GTFSRealtime.FeedHeader
  field :entity, 2, repeated: true, type: Poller.GTFSRealtime.FeedEntity
end

defmodule Poller.GTFSRealtime.FeedHeader do
  use Protobuf, syntax: :proto2

  field :gtfs_realtime_version, 1, required: true, type: :string
  field :incrementality, 2, optional: true, type: :int32
  field :timestamp, 3, optional: true, type: :uint64
end

defmodule Poller.GTFSRealtime.FeedEntity do
  use Protobuf, syntax: :proto2

  field :id, 1, required: true, type: :string
  field :is_deleted, 2, optional: true, type: :bool
  field :trip_update, 3, optional: true, type: Poller.GTFSRealtime.TripUpdate
end

defmodule Poller.GTFSRealtime.TripUpdate do
  use Protobuf, syntax: :proto2

  field :trip, 1, required: true, type: Poller.GTFSRealtime.TripDescriptor
  field :stop_time_update, 2, repeated: true, type: Poller.GTFSRealtime.StopTimeUpdate
  field :timestamp, 4, optional: true, type: :uint64
  field :delay, 5, optional: true, type: :int32
end

defmodule Poller.GTFSRealtime.TripDescriptor do
  use Protobuf, syntax: :proto2

  # schedule_relationship: 0 SCHEDULED, 1 ADDED, 2 UNSCHEDULED, 3 CANCELED
  field :trip_id, 1, optional: true, type: :string
  field :start_time, 2, optional: true, type: :string
  field :start_date, 3, optional: true, type: :string
  field :schedule_relationship, 4, optional: true, type: :int32
  field :route_id, 5, optional: true, type: :string
  field :direction_id, 6, optional: true, type: :uint32
end

defmodule Poller.GTFSRealtime.StopTimeUpdate do
  use Protobuf, syntax: :proto2

  # schedule_relationship: 0 SCHEDULED, 1 SKIPPED, 2 NO_DATA
  field :stop_sequence, 1, optional: true, type: :uint32
  field :arrival, 2, optional: true, type: Poller.GTFSRealtime.StopTimeEvent
  field :departure, 3, optional: true, type: Poller.GTFSRealtime.StopTimeEvent
  field :stop_id, 4, optional: true, type: :string
  field :schedule_relationship, 5, optional: true, type: :int32
end

defmodule Poller.GTFSRealtime.StopTimeEvent do
  use Protobuf, syntax: :proto2

  field :delay, 1, optional: true, type: :int32
  field :time, 2, optional: true, type: :int64
  field :uncertainty, 3, optional: true, type: :int32
end
