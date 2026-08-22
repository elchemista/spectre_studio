defmodule SpectreStudioWeb.ConnectionLive.Show do
  @moduledoc """
  One connection: what it granted, which Agents it exposes, what it is doing.

  The event log is a stream. A busy connection emits a line per frame, and
  re-rendering two hundred of them on each one would make the panel slower the
  longer it stays open.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Pulse
  alias SpectreStudio.Pulse.Agent
  alias SpectreStudio.Pulse.Events
  alias SpectreStudio.Pulse.Scopes

  @event_limit 200

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Pulse.fetch(id) do
      {:ok, connection} ->
        if connected?(socket), do: Events.subscribe(Events.connection_topic(id))

        {:ok,
         socket
         |> assign(:page_title, connection.label)
         |> assign(:active_section, :connections)
         |> assign(:active_connection, id)
         |> assign_connection(connection)
         |> stream(:events, Enum.reverse(connection.events), limit: -@event_limit)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "That connection no longer exists.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("connect", _params, socket) do
    Pulse.connect(socket.assigns.connection.id)
    {:noreply, socket}
  end

  def handle_event("disconnect", _params, socket) do
    Pulse.disconnect(socket.assigns.connection.id)
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info({:connection_event, _id, event}, socket) do
    {:noreply, stream_insert(socket, :events, event, at: -1, limit: -@event_limit)}
  end

  def handle_info({:connection_status, _id, _status}, socket), do: {:noreply, reload(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  defp reload(socket) do
    case Pulse.fetch(socket.assigns.connection.id) do
      {:ok, connection} -> assign_connection(socket, connection)
      :error -> push_navigate(socket, to: ~p"/")
    end
  end

  defp assign_connection(socket, connection) do
    socket
    |> assign(:connection, connection)
    |> assign(:scopes, Scopes.partition(connection.manifest))
    |> assign(:agents, agents(connection))
  end

  defp agents(%{manifest: nil}), do: []
  defp agents(%{manifest: manifest}), do: manifest.agents

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      connections={@connections}
      active_section={@active_section}
      active_connection={@active_connection}
    >
      <.header>
        {@connection.label}
        <:subtitle>{@connection.display_url}</:subtitle>
        <:actions>
          <div class="flex flex-wrap items-center gap-3">
            <.led state={Pulse.led_state(@connection.status)}>{@connection.status}</.led>
            <.button
              :if={@connection.status not in [:ready, :connecting, :authenticating]}
              variant="primary"
              phx-click="connect"
            >
              connect
            </.button>
            <.button
              :if={@connection.status in [:ready, :connecting, :authenticating, :degraded]}
              phx-click="disconnect"
            >
              disconnect
            </.button>
          </div>
        </:actions>
      </.header>

      <p :if={@connection.last_error} class="mt-5 term-out text-[0.78rem] t-fail">
        {@connection.last_error}
      </p>

      <div class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_24rem]">
        <div class="space-y-6">
          <.term_window title="manifest" status={manifest_status(@connection)}>
            <p :if={is_nil(@connection.manifest)} class="term-comment text-[0.8rem] t-faint">
              no manifest yet — it arrives once the socket authenticates
            </p>

            <.list :if={@connection.manifest}>
              <:item title="principal">
                {@connection.manifest.principal_id} · {@connection.manifest.principal_identity}
              </:item>
              <:item title="transport">
                {@connection.manifest.transport} · {@connection.manifest.spec_mode}
              </:item>
              <:item title="connected at">{@connection.manifest.connected_at}</:item>
              <:item title="profiles">
                {Enum.join(@connection.manifest.granted_profiles, ", ")}
              </:item>
            </.list>

            <div class="mt-5 space-y-3">
              <p class="term-label">granted</p>
              <div class="flex flex-wrap gap-2">
                <.scope_badge :for={scope <- @scopes.granted} scope={scope} granted />
                <span :if={@scopes.granted == []} class="term-comment t-faint">none</span>
              </div>

              <p class="term-label mt-4">withheld</p>
              <div class="flex flex-wrap gap-2">
                <.scope_badge :for={scope <- @scopes.withheld} scope={scope} granted={false} />
              </div>
              <p class="term-comment text-[0.68rem] t-faint">
                a withheld scope is why a panel is missing — only agent.runtime.* are enforced by Pulse itself,
                the rest are application scopes the host defines
              </p>
            </div>
          </.term_window>

          <.term_window title="exposed agents" status={"#{length(@agents)} agents"}>
            <p :if={@agents == []} class="term-comment text-[0.8rem] t-faint">
              no agents exposed on this connection
            </p>

            <.table :if={@agents != []} id="agents" rows={@agents}>
              <:col :let={agent} label="address">
                <.link
                  navigate={
                    ~p"/connections/#{@connection.id}/agents/#{Agent.encode_address(agent.address)}"
                  }
                  class="t-strong underline decoration-dashed underline-offset-4"
                >
                  {agent.address}
                </.link>
              </:col>
              <:col :let={agent} label="display">{agent.display_name}</:col>
              <:col :let={agent} label="capabilities">
                <span class="t-dim">{Enum.join(agent.capabilities, ", ")}</span>
              </:col>
              <:col :let={agent} label="proto">
                <span class="tabular t-dim">{Enum.join(agent.protocol_versions, ", ")}</span>
              </:col>
            </.table>
          </.term_window>
        </div>

        <.term_window title="events" status="live" body_class="!p-0">
          <.stream id="connection-events" events={@streams.events} class="px-4" />
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  defp manifest_status(%{manifest: nil}), do: "pending"
  defp manifest_status(%{manifest: manifest}), do: String.slice(manifest.connection_id, 0, 8)
end
