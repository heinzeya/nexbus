# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :core, Core.Repo,
  database: "nexbus_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost"

config :core, gtfs_timezone: "America/Vancouver"

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :core, Core.Cache,
  # Create a new generation every 12h; entries in the oldest are dropped
  gc_interval: :timer.hours(12),
  max_size: 1_000_000,
  allocated_memory: 2_000_000_000,
  gc_memory_check_interval: :timer.seconds(10)

config :poller,
  gtfs_realtime_url: "https://gtfsapi.translink.ca/v3/gtfsrealtime"

config :poller, Poller.Scheduler,
  jobs: [
    refresh_stop_boards: [
      schedule: {:extended, "*/30 * * * * *"},
      task: {Poller.Jobs.RefreshStopBoards, :run, []}
    ]
  ]

config :datahub,
  gtfs_url: "https://gtfs-static.translink.ca/gtfs/google_transit.zip"

config :scheduler, Oban,
  repo: Core.Repo,
  queues: [default: 10],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]

config :bus_stop,
  ecto_repos: [Core.Repo],
  generators: [context_app: false]

# Configures the endpoint
config :bus_stop, BusStop.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BusStop.ErrorHTML, json: BusStop.ErrorJSON],
    layout: false
  ],
  pubsub_server: Core.PubSub,
  live_view: [signing_salt: "rue5PxwY"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  bus_stop: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/bus_stop/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  bus_stop: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/bus_stop", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Sample configuration:
#
#     config :logger, :default_handler,
#       level: :info
#
#     config :logger, :default_formatter,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#
import Config


# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
