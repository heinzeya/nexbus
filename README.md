# Nexbus

Live bus-stop departure boards for TransLink (Metro Vancouver).

Nexbus loads TransLink's GTFS static timetable into Postgres, polls the
GTFS-realtime trip-updates feed, and serves a Phoenix LiveView page per stop
that updates itself every 30 seconds. Open `/busstops/<stop_code>` and you get
the next six departures with live predictions where TransLink has them, and
scheduled times where it doesn't.

```
http://localhost:4000/busstops/50001
http://localhost:4000/busstops/50001?theme=led
```

## How it works

```
 TransLink GTFS static (.zip)          TransLink GTFS-realtime (protobuf)
            │                                         │
            ▼                                         ▼
   ┌─────────────────┐                     ┌────────────────────┐
   │ datahub         │                     │ poller             │
   │ Datahub.GTFS    │                     │ Quantum, every 30s │
   │ load_gtfs_file  │                     │ TripUpdates        │
   └────────┬────────┘                     └─────────┬──────────┘
            │ insert_all                             │ put_trip_updates
            ▼                                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ core                                                         │
   │  Postgres gtfs_* tables   Core.Cache (Nebulex)   Core.PubSub │
   │  Core.GTFS  ──►  Core.Realtime  ──►  Core.StopBoard          │
   └──────────────────────────────┬───────────────────────────────┘
                                  │ {:stop_board, board} broadcast
                                  ▼
                        ┌───────────────────┐
                        │ bus_stop          │
                        │ StopLive + themes │
                        └───────────────────┘
```

1. **Timetable load (manual).** `Datahub.GTFS.load_gtfs_file/2` downloads the
   static feed, unzips it, and bulk-inserts stops, routes, trips, stop times,
   calendar and calendar dates. Every row is stamped with a `version` date
   (the feed's publish date), so several feeds live side by side and a new
   publish never overwrites an old one.
2. **Viewer subscribes.** When a browser opens `/busstops/:stop_code`,
   `BusStop.StopLive` calls `Core.StopBoard.subscribe/1`. That registers the
   stop in `Core.StopBoard.Registry` and subscribes the LiveView process to
   the `stop_board:<code>` PubSub topic. The first render uses
   `Core.StopBoard.fetch/1` (cached, or built on a miss).
3. **Polling.** Every 30 seconds `Poller.Jobs.RefreshStopBoards` checks which
   stops are being watched. If none, it does nothing. Otherwise it fetches
   realtime trip updates once, stores them in the cache, then rebuilds and
   broadcasts each watched stop's board.
4. **Building a board.** `Core.GTFS.upcoming_departures/3` picks the schedule
   version for today, works out which services run (calendar plus
   exceptions), and queries departures, including after-midnight trips from
   the previous service day. `Core.Realtime.apply_trip_updates/2` then
   shifts times by the live delays, drops cancelled trips and skipped stops,
   and the board keeps the next six departures.
5. **Rendering.** `BusStop.StopBoard.View` turns the board into
   display-ready strings (route label, minutes to departure, local clock
   times, "3 min late"). A theme module renders that view. Themes contain
   markup only and no departure logic.

The poller only works for stops someone is looking at, so idle stops cost
nothing.

## Umbrella apps

| App | Role | Key modules |
| --- | --- | --- |
| [core](apps/core) | Shared data layer: Ecto repo, GTFS schemas and queries, realtime merging, cache, PubSub, stop-board registry | `Core.GTFS`, `Core.Realtime`, `Core.StopBoard`, `Core.Cache` |
| [datahub](apps/datahub) | Imports GTFS static feeds into Postgres using a parallel Flow pipeline | `Datahub.GTFS` |
| [poller](apps/poller) | Scheduled jobs: fetches GTFS-realtime and refreshes watched boards | `Poller.Scheduler`, `Poller.TripUpdates`, `Poller.Jobs.RefreshStopBoards` |
| [bus_stop](apps/bus_stop) | Phoenix web app: the stop board LiveView and its themes | `BusStop.StopLive`, `BusStop.StopBoard.View`, `BusStop.StopBoard.Theme` |

`datahub`, `poller` and `bus_stop` depend on `core`. They don't depend on
each other.

## Getting started

### Requirements

- Elixir 1.20 / Erlang OTP 29 (the apps declare `elixir: "~> 1.20"`)
- PostgreSQL. The default dev credentials are `postgres` / `postgres` on
  `localhost`, database `nexbus_dev` (see [config/config.exs](config/config.exs)).
- Optional: a [TransLink Open API](https://developer.translink.ca/) key for
  realtime predictions.

### Setup

```sh
mix deps.get
(cd apps/bus_stop && mix assets.setup)   # installs tailwind + esbuild
mix ecto.create
mix ecto.migrate
```

### Load the timetable

The static feed is not loaded automatically. Load it once, and again
whenever TransLink publishes a new one:

```sh
iex -S mix
```

```elixir
# Default: downloads TransLink's google_transit.zip
Datahub.GTFS.load_gtfs_file()

# From a local zip
Datahub.GTFS.load_gtfs_file("/path/to/google_transit.zip")

# Force a version date
Datahub.GTFS.load_gtfs_file("google_transit.zip", version: ~D[2026-10-16])
```

`stop_times.txt` has millions of rows, so expect the load to take a while. If
a load fails part way, re-run it. It deletes that version's rows first, and
other versions are untouched.

### Run

```sh
export TRANSLINK_API_KEY=your-key   # optional; without it boards show scheduled times
iex -S mix phx.server
```

Then open <http://localhost:4000/busstops/50001>. The stop code is the
5-digit number posted on the stop sign. LiveDashboard is at
<http://localhost:4000/dev/dashboard> in dev.

### Test

```sh
mix test
```

Scheduled poller jobs are disabled in the test environment.

## Configuration

| Setting | Where | Default |
| --- | --- | --- |
| Database | `config :core, Core.Repo` | `nexbus_dev` on localhost |
| Feed timezone | `config :core, gtfs_timezone:` | `America/Vancouver` |
| Static feed URL | `config :datahub, gtfs_url:` | TransLink `google_transit.zip` |
| Realtime feed URL | `config :poller, gtfs_realtime_url:` | TransLink `v3/gtfsrealtime` |
| Realtime API key | `TRANSLINK_API_KEY` env var ([runtime.exs](config/runtime.exs)) | none (scheduled only) |
| Poll interval | `config :poller, Poller.Scheduler, jobs:` | every 30 s |
| Board themes | `config :bus_stop, BusStop.StopBoard.Theme` | default `eink` |
| Production secret | `SECRET_KEY_BASE` env var | required in prod |

## Board themes

Pick a theme with `?theme=<key>`. Unknown or missing keys fall back to the
default.

| Key | Look | Good for |
| --- | --- | --- |
| `eink` (default) | Black on paper white, no greys, no animation | E-ink displays |
| `led` | Amber monospace on black, "Due" pulses | Backlit screens read from a distance |
| `transit` | Light and colourful, a badge per route, live-status pills | Phones and full-colour displays |

Departures without a live prediction are marked as scheduled (for example
`m*` on the LED board).

## Key concepts

- **Service day.** GTFS times are seconds from the start of a service day,
  which is noon minus 12 hours in the feed timezone. Times like `25:10:00`
  are valid and mean 1:10 the next morning. That's why boards also query
  the previous service day.
- **Versions.** All `gtfs_*` tables have a composite primary key that
  starts with `version`. `Core.GTFS.version_for/1` uses the newest version
  published on or before the given date, so a feed loaded ahead of time
  goes live on its publish date.
- **Realtime fallback.** A stop with no update of its own takes the delay
  of the nearest earlier updated stop on the same trip, as the
  GTFS-realtime spec says. Trip updates stay cached for 3 minutes. If the
  poller stops, boards revert to scheduled times.
- **Lookback.** Boards fetch departures scheduled up to 30 minutes in the
  past, so a late bus still shows once its delay is applied.

## Extending

See [docs/extending.md](docs/extending.md) for step-by-step guides:

- Add a board theme
- Add a scheduled poller job
- Import another GTFS file or column
- Point Nexbus at a different transit agency
- Add a JSON API
- Add a new umbrella app
