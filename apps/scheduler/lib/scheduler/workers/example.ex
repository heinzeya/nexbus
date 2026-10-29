defmodule Scheduler.Workers.Example do
  @moduledoc """
  Example Oban worker. Enqueue with:

      %{"message" => "hello"}
      |> Scheduler.Workers.Example.new()
      |> Oban.insert()
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("Scheduler.Workers.Example ran with #{inspect(args)}")
    :ok
  end
end
