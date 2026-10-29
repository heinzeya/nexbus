defmodule Core.Cache do
  @moduledoc """
  Local in-memory cache backed by Nebulex.
  """

  use Nebulex.Cache,
    otp_app: :core,
    adapter: Nebulex.Adapters.Local
end
