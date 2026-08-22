defmodule SpectreStudioWeb.AgentLive.Events do
  @moduledoc """
  The connection's event log, seen from an Agent panel.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell
  import SpectreStudioWeb.StudioComponents

  alias SpectreStudioWeb.AgentLive.Shell

  @event_limit 200

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :events) do
      {:ok, socket} ->
        events = Enum.reverse(socket.assigns.connection.events)
        {:ok, stream(socket, :events, events, limit: -@event_limit)}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:connection_event, _id, event}, socket) do
    {:noreply, stream_insert(socket, :events, event, at: -1, limit: -@event_limit)}
  end

  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      connections={@connections}
      active_section={@active_section}
      active_connection={@active_connection}
    >
      <.agent_header connection={@connection} agent={@agent} tab={@tab} />

      <div class="mt-6">
        <.term_window title="events" status="live" body_class="!p-0">
          <.stream id="agent-events" events={@streams.events} class="max-h-[32rem] px-4" />
        </.term_window>
      </div>
    </Layouts.app>
    """
  end
end
