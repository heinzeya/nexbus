defmodule Poller.Scheduler do
  @moduledoc """
  Quantum scheduler for periodic polling jobs.

  Jobs are configured under `config :poller, Poller.Scheduler, jobs: [...]`.
  """

  use Quantum, otp_app: :poller
end
