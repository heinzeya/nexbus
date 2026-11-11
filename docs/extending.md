# Extending Nexbus

Step-by-step guides for the most common changes. Read the
[README](../README.md) first for how data moves through the system.

The ground rule: **put logic in `core`, keep the other apps thin.**
`datahub` writes data, `poller` triggers refreshes, `bus_stop` displays
data. Anything two apps need belongs in `core`.

- [Add a board theme](#add-a-board-theme)
- [Add a scheduled poller job](#add-a-scheduled-poller-job)
- [Import another GTFS file or column](#import-another-gtfs-file-or-column)
- [Point Nexbus at a different transit agency](#point-nexbus-at-a-different-transit-agency)
- [Add a JSON API](#add-a-json-api)
- [Add a new umbrella app](#add-a-new-umbrella-app)

---

## Add a board theme

A theme is a module with one function component, `render/1`. It gets a
single `@board` assign, a `BusStop.StopBoard.View` struct where every value
is already formatted. A theme never computes times or sorts departures.

### 1. Create the module

`apps/bus_stop/lib/bus_stop/stop_board/themes/mono.ex`:

```elixir
defmodule BusStop.StopBoard.Themes.Mono do
  @moduledoc "Minimal white-on-black list."

  use BusStop.StopBoard.Theme, label: "Mono"

  @impl true
  def render(assigns) do
    ~H"""
    <main class="min-h-screen bg-black p-6 font-mono text-white">
      <h1 class="text-2xl">
        {if @board.found?, do: @board.stop_name, else: "Stop #{@board.stop_code} not found"}
      </h1>
      <ol>
        <li :for={d <- @board.departures} class="flex justify-between py-2">
          <span>{d.route} {d.headsign}</span>
          <span>{if d.minutes == 0, do: "Due", else: "#{d.minutes} min"}</span>
        </li>
      </ol>
      <p :if={@board.found? && @board.departures == []}>No departures in the next 2 hours</p>
      <footer class="text-xs opacity-60">Updated {@board.updated_at}</footer>
    </main>
    """
  end
end
```

`use BusStop.StopBoard.Theme` brings in `use BusStop, :html` (HEEx, core
components) and declares the behaviour. The `label:` option is required.

### 2. Register it

Pick one of these:

- **Built-in theme:** add it to the `@builtin` map in
  [theme.ex](../apps/bus_stop/lib/bus_stop/stop_board/theme.ex).
- **From config:** no core code changes, and config can also replace a
  built-in key or change the default:

  ```elixir
  config :bus_stop, BusStop.StopBoard.Theme,
    default: "mono",
    themes: %{"mono" => BusStop.StopBoard.Themes.Mono}
  ```

### 3. Try it

Open `/busstops/50001?theme=mono`.

### What `@board` contains

| Field | Example |
| --- | --- |
| `stop_code`, `stop_name` | `"50001"`, `"Granville St @ W Georgia St"` |
| `found?` | `false` when the stop isn't in the current schedule |
| `clock`, `updated_at` | `"09:52"`, `"09:52:30"` (feed timezone) |
| `departures` | list of maps, sorted by route then time |

Each departure has:

| Field | Example |
| --- | --- |
| `route` | `"23"`, `"N19"` (leading zeros stripped) |
| `headsign` | `"Pacific/To English Bay"` (route prefix removed) |
| `minutes` | `0` means due |
| `realtime?` | `true` if the time is a live prediction |
| `scheduled`, `eta` | `"09:52"`, `"10:00"` |
| `delay` | `"on time"`, `"8 min late"`, or `nil` |
| `status` | `"Scheduled 09:52 · ETA 10:00 (8 min late)"` |

If a theme needs a value that isn't here, add it in
[view.ex](../apps/bus_stop/lib/bus_stop/stop_board/view.ex) so every theme
can use it. Don't compute it in the template.

### 4. Test it

Add a case to
[theme_test.exs](../apps/bus_stop/test/bus_stop/stop_board/theme_test.exs)
that renders the theme with both a found board and a `found?: false` board.

---

## Add a scheduled poller job

Jobs run on [Quantum](https://hexdocs.pm/quantum) through `Poller.Scheduler`.

### 1. Write the job

A job is a plain module function. Return quickly and don't raise for
expected failures: log them and return an error tuple.

`apps/poller/lib/poller/jobs/refresh_gtfs.ex`:

```elixir
defmodule Poller.Jobs.RefreshGtfs do
  @moduledoc "Reloads the GTFS static feed nightly."
  require Logger

  def run do
    case Datahub.GTFS.load_gtfs_file() do
      {:ok, %{version: v}} -> Logger.info("GTFS #{v} loaded")
      {:error, reason} -> Logger.error("GTFS reload failed: #{inspect(reason)}")
    end
  end
end
```

> This example calls `datahub` from `poller`. Add
> `{:datahub, in_umbrella: true}` to `apps/poller/mix.exs` first, or put the
> job in `datahub` with its own scheduler.

### 2. Schedule it

In [config/config.exs](../config/config.exs):

```elixir
config :poller, Poller.Scheduler,
  jobs: [
    refresh_stop_boards: [
      schedule: {:extended, "*/30 * * * * *"},   # extended = with seconds
      task: {Poller.Jobs.RefreshStopBoards, :run, []}
    ],
    refresh_gtfs: [
      schedule: "0 4 * * *",                     # 04:00 every day
      timezone: "America/Vancouver",
      task: {Poller.Jobs.RefreshGtfs, :run, []}
    ]
  ]
```

[config/test.exs](../config/test.exs) sets `jobs: []`, so jobs never run
during tests. In tests, call `run/0` directly.

---

## Import another GTFS file or column

Example: importing `shapes.txt`. The same steps apply when you add a column
to an existing table.

### 1. Migration

Every GTFS table needs `version` as the first part of its primary key.

```sh
cd apps/core && mix ecto.gen.migration create_gtfs_shapes -r Core.Repo
```

This creates the file in `apps/core/priv/repo/migrations/`.

```elixir
def change do
  create table(:gtfs_shapes, primary_key: false) do
    add :version, :date, primary_key: true
    add :shape_id, :string, primary_key: true
    add :shape_pt_sequence, :integer, primary_key: true
    add :latitude, :float, null: false
    add :longitude, :float, null: false
  end
end
```

### 2. Schema in `core`

`apps/core/lib/core/gtfs/shape.ex`, following
[stop.ex](../apps/core/lib/core/gtfs/stop.ex):

```elixir
defmodule Core.GTFS.Shape do
  use Ecto.Schema
  @primary_key false

  schema "gtfs_shapes" do
    field :version, :date, primary_key: true
    field :shape_id, :string, primary_key: true
    field :shape_pt_sequence, :integer, primary_key: true
    field :latitude, :float
    field :longitude, :float
  end
end
```

### 3. Loader in `datahub`

In [datahub/gtfs.ex](../apps/datahub/lib/datahub/gtfs.ex):

1. Add the schema to `alias Core.GTFS.{...}`.
2. Add `{"shapes.txt", Shape}` to `@tables`. This also adds the file to
   the unzip list.
3. Add a `to_row/2` clause that maps CSV columns to fields. Use the
   existing helpers: `string/1` (blank becomes `nil`), `integer/1`,
   `float/1`, `date/1` (`YYYYMMDD`), `seconds/1` (`HH:MM:SS`, can be past 24h).

   ```elixir
   defp to_row(Shape, r) do
     %{
       shape_id: r["shape_id"],
       shape_pt_sequence: integer(r["shape_pt_sequence"]),
       latitude: float(r["shape_pt_lat"]),
       longitude: float(r["shape_pt_lon"])
     }
   end
   ```

The batch size is worked out from the schema's field count, so wide tables
stay under Postgres's 65,535 bind-parameter limit with no further changes.

### 4. Query in `core`

Add read functions to `Core.GTFS`. Always filter by `version` (use
`version_for/1`) and join on `version` as well as the ID.

### 5. Reload

```sh
mix ecto.migrate
iex -S mix
```

```elixir
Datahub.GTFS.load_gtfs_file()
```

---

## Point Nexbus at a different transit agency

Any agency that publishes GTFS static and GTFS-realtime trip updates should
work. Things to change:

| What | Where |
| --- | --- |
| Static feed URL | `config :datahub, gtfs_url:` |
| Feed timezone | `config :core, gtfs_timezone:` (it must match `agency_timezone` in `agency.txt`) |
| Realtime URL | `config :poller, gtfs_realtime_url:` |
| API key, and how it's sent | `Poller.TripUpdates.fetch/1` sends it as the `?apikey=` query param. Change this if the agency uses a header. Rename the env var in [runtime.exs](../config/runtime.exs). |
| Version date | `Datahub.GTFS.feed_version_date/1` reads the trailing `YYYYMMDD` of `feed_version`. Other agencies format this differently. If it doesn't match, the loader uses the newest file date in the zip, or you can pass `version:` explicitly. |
| Route/headsign cleanup | `BusStop.StopBoard.View.route_label/1` strips TransLink's zero padding (`"023"` → `"23"`). `headsign/1` strips the repeated route prefix. Both do nothing on feeds without these quirks, but check them. |
| Stop lookup | The URL uses `stop_code` (the number on the sign). If the feed leaves `stop_code` empty, look stops up by `stop_id` in `Core.GTFS.get_stop_by_code/2`. |

Realtime decoding uses a small subset of the GTFS-realtime proto, defined in
[gtfs_realtime.ex](../apps/poller/lib/poller/gtfs_realtime.ex). Undeclared
fields are skipped, so agency extensions don't break decoding.

---

## Add a JSON API

The router already has an `:api` pipeline. Boards come from
`Core.StopBoard.fetch/1`, which serves from the cache and builds on a miss.

`apps/bus_stop/lib/bus_stop/controllers/board_json_controller.ex`:

```elixir
defmodule BusStop.BoardJSONController do
  use BusStop, :controller

  def show(conn, %{"stop_code" => code}) do
    case Core.StopBoard.fetch(code) do
      {:ok, board} ->
        view = BusStop.StopBoard.View.build(code, {:ok, board})
        json(conn, Map.from_struct(view))

      {:error, :stop_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "stop_not_found"})
    end
  end
end
```

In [router.ex](../apps/bus_stop/lib/bus_stop/router.ex):

```elixir
scope "/api", BusStop do
  pipe_through :api
  get "/stops/:stop_code/board", BoardJSONController, :show
end
```

An API request does **not** subscribe, so the poller won't keep that stop
fresh. The cache entry expires after 2 minutes and is then rebuilt on the
next request, with whatever realtime data the cache holds. If API clients
need fresh data for stops nobody is viewing, add those stops to the list in
`Poller.Jobs.RefreshStopBoards`.

---

## Add a new umbrella app

```sh
cd apps
mix new my_app --sup
```

Then:

1. In `apps/my_app/mix.exs`, keep the generated umbrella paths
   (`build_path`, `config_path`, `deps_path`, `lockfile`) and add
   `{:core, in_umbrella: true}` if the app needs the repo, cache or PubSub.
2. Put its config in the shared [config/](../config) files under
   `config :my_app, ...`. Umbrella apps share one config.
3. Use `Core.Repo`, `Core.Cache` and `Core.PubSub` instead of starting
   your own. They're started by `Core.Application`.
4. If it runs periodic work, either add jobs to `Poller.Scheduler` or start
   its own `use Quantum, otp_app: :my_app` scheduler. Disable it in
   `config/test.exs` the same way.

Migrations always go in `apps/core/priv/repo/migrations/`, whichever app
uses the table.
