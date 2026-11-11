defmodule BusStop.StopBoard.ThemeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BusStop.StopBoard.{Theme, View}

  @now ~U[2026-11-07 18:00:00Z]

  defp board do
    {:ok,
     %{
       stop: %{stop_name: "Granville St @ W Georgia St"},
       generated_at: @now,
       departures: [
         %{
           route: "023",
           headsign: "23 Pacific/To English Bay",
           scheduled_at: ~U[2026-11-07 18:02:00Z],
           departs_at: ~U[2026-11-07 18:05:00Z],
           realtime?: true,
           delay: 180
         },
         %{
           route: "009",
           headsign: "9 Boundary",
           scheduled_at: ~U[2026-11-07 18:00:30Z],
           departs_at: ~U[2026-11-07 18:00:30Z],
           realtime?: false,
           delay: 0
         }
       ]
     }}
  end

  describe "View.build/3" do
    test "formats and sorts departures" do
      view = View.build("50001", board(), @now)

      assert view.found?
      assert [%{route: "9", minutes: 0, delay: nil}, %{route: "23"} = d23] = view.departures
      assert d23.headsign == "Pacific/To English Bay"
      assert d23.minutes == 5
      assert d23.delay == "3 min late"
      assert d23.status =~ "(3 min late)"
    end

    test "marks a missing stop" do
      view = View.build("99999", {:error, :stop_not_found}, @now)
      refute view.found?
      assert view.departures == []
    end
  end

  describe "resolve/1" do
    test "returns a known theme" do
      assert {"led", BusStop.StopBoard.Themes.Led} = Theme.resolve("led")
    end

    test "falls back to the default" do
      assert {"eink", BusStop.StopBoard.Themes.Eink} = Theme.resolve("nope")
      assert {"eink", _} = Theme.resolve(nil)
    end
  end

  test "every theme renders found and missing boards" do
    for {_key, module} <- Theme.all() do
      html = render_component(&module.render/1, board: View.build("50001", board(), @now))
      assert html =~ "Granville St"
      assert html =~ "English Bay"

      html = render_component(&module.render/1, board: View.build("99999", {:error, :stop_not_found}, @now))
      assert html =~ "99999"
    end
  end
end
