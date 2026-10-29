defmodule BusStop.PageController do
  use BusStop, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
