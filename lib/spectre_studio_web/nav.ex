defmodule SpectreStudioWeb.Nav do
  @moduledoc """
  Keeps the navigation rail in step with the connections that actually exist.

  Mounted once per `live_session`, so every panel shows the same set of
  endpoints and the same LED for each of them without repeating the wiring.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias SpectreStudio.Pulse
  alias SpectreStudio.Pulse.Events

  @doc false
  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Events.subscribe(Events.directory_topic())
    end

    {:cont,
     socket
     |> assign(:connections, rail_entries())
     |> assign_new(:active_section, fn -> nil end)
     |> assign_new(:active_connection, fn -> nil end)
     |> attach_hook(:studio_nav, :handle_info, &handle_nav_info/2)}
  end

  # The rail is refreshed here and the message continues on: a panel showing the
  # same connections needs to react to the change too.
  defp handle_nav_info(:directory_changed, socket) do
    {:cont, assign(socket, :connections, rail_entries())}
  end

  defp handle_nav_info(_message, socket), do: {:cont, socket}

  @doc "The rail projection of every configured connection."
  @spec rail_entries() :: [map()]
  def rail_entries do
    Enum.map(Pulse.list(), fn connection ->
      %{id: connection.id, label: connection.label, state: Pulse.led_state(connection.status)}
    end)
  end
end
