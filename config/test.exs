import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bus_stop, BusStop.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZPDJVkY+aP9DidxWpAfwgzb8l+AbFhBrJznR9QcAgAQ/Ns1yFMZbVysK6lYjx2KT",
  server: false

# Run Oban jobs manually in tests (use Oban.Testing helpers)
config :scheduler, Oban, testing: :manual

# Don't run scheduled poller jobs in tests
config :poller, Poller.Scheduler, jobs: []
