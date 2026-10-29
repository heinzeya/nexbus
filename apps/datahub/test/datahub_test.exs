defmodule DatahubTest do
  use ExUnit.Case
  doctest Datahub

  test "greets the world" do
    assert Datahub.hello() == :world
  end
end
