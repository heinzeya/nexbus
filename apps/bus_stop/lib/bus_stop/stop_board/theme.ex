defmodule BusStop.StopBoard.Theme do
  @moduledoc """
  A visual theme for the stop departures board.

  A theme is a module with a `render/1` function component. It receives a
  single `@board` assign, a `BusStop.StopBoard.View` with every value already
  formatted, so a theme holds markup only and no departure logic.

  ## Writing a theme

      defmodule BusStop.StopBoard.Themes.Mine do
        use BusStop.StopBoard.Theme, label: "Mine"

        def render(assigns) do
          ~H\"\"\"
          <ol><li :for={d <- @board.departures}>{d.route} {d.minutes}</li></ol>
          \"\"\"
        end
      end

  Then register it under a key in config:

      config :bus_stop, BusStop.StopBoard.Theme,
        default: "eink",
        themes: %{"mine" => BusStop.StopBoard.Themes.Mine}

  Configured themes are merged over the built-in ones, so a key can also
  replace a built-in theme. A board picks its theme with `?theme=<key>`.
  """

  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback label() :: String.t()

  @builtin %{
    "eink" => BusStop.StopBoard.Themes.Eink,
    "led" => BusStop.StopBoard.Themes.Led,
    "transit" => BusStop.StopBoard.Themes.Transit
  }

  defmacro __using__(opts) do
    label = Keyword.fetch!(opts, :label)

    quote do
      use BusStop, :html
      @behaviour BusStop.StopBoard.Theme

      @impl BusStop.StopBoard.Theme
      def label, do: unquote(label)
    end
  end

  @doc "All available themes, keyed by the name used in `?theme=`."
  def all, do: Map.merge(@builtin, Keyword.get(config(), :themes, %{}))

  def default_key, do: Keyword.get(config(), :default, "eink")

  @doc """
  Returns `{key, module}` for `key`, falling back to the default theme when
  `key` is nil or unknown.
  """
  def resolve(key) do
    themes = all()

    case themes do
      %{^key => module} -> {key, module}
      _ -> {default_key(), Map.fetch!(themes, default_key())}
    end
  end

  defp config, do: Application.get_env(:bus_stop, __MODULE__, [])
end
