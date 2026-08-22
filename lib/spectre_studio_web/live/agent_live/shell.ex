defmodule SpectreStudioWeb.AgentLive.Shell do
  @moduledoc """
  What the four Agent panels share: how they mount, and the header above them.

  Each tab is its own LiveView rather than a branch inside one. That is what
  makes the monitoring lifecycle honest — the subscription lives exactly as long
  as the process that owns the panel, so leaving the tab ends the stream without
  any bookkeeping, and no other panel carries the cost of a socket it is not
  using.
  """

  use SpectreStudioWeb, :html

  import SpectreStudioWeb.StudioComponents

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias SpectreStudio.Pulse
  alias SpectreStudio.Pulse.Agent
  alias SpectreStudio.Pulse.Events
  alias SpectreStudio.Pulse.Manifest
  alias SpectreStudio.Pulse.Scopes

  @tabs [
    %{key: :overview, label: "overview", capability: nil},
    %{key: :monitor, label: "live", capability: :monitor_stream},
    %{key: :messages, label: "messages", capability: :message_send},
    %{key: :events, label: "events", capability: nil}
  ]

  @doc """
  Loads the connection and the Agent for one panel.

  Returns `{:ok, socket}`, or a socket already redirecting when the connection,
  the manifest or the Agent is not there.
  """
  @spec mount_agent(LiveView.Socket.t(), map(), atom()) ::
          {:ok, LiveView.Socket.t()} | {:redirect, LiveView.Socket.t()}
  def mount_agent(socket, %{"id" => id, "address" => encoded}, tab) do
    with {:ok, address} <- Agent.decode_address(encoded),
         {:ok, connection} <- Pulse.fetch(id),
         %Manifest{} = manifest <- connection.manifest,
         {:ok, agent} <- Manifest.fetch_agent(manifest, address) do
      if LiveView.connected?(socket), do: Events.subscribe(Events.connection_topic(id))

      {:ok,
       socket
       |> Component.assign(:page_title, agent.display_name)
       |> Component.assign(:active_section, :connections)
       |> Component.assign(:active_connection, id)
       |> Component.assign(:connection, connection)
       |> Component.assign(:agent, agent)
       |> Component.assign(:tab, tab)}
    else
      nil -> {:redirect, redirect_to(socket, id, "No manifest yet — connect first.")}
      :error -> {:redirect, redirect_to(socket, id, "That Agent is not exposed here.")}
    end
  end

  defp redirect_to(socket, id, message) do
    socket
    |> LiveView.put_flash(:error, message)
    |> LiveView.push_navigate(to: "/connections/#{id}")
  end

  @doc "Refreshes the connection projection after a status or event change."
  @spec reload(LiveView.Socket.t()) :: LiveView.Socket.t()
  def reload(socket) do
    case Pulse.fetch(socket.assigns.connection.id) do
      {:ok, connection} -> Component.assign(socket, :connection, connection)
      :error -> LiveView.push_navigate(socket, to: "/")
    end
  end

  @doc "The path of one tab for one Agent."
  @spec tab_path(map(), Agent.t(), atom()) :: String.t()
  def tab_path(connection, agent, tab) do
    base = "/connections/#{connection.id}/agents/#{Agent.encode_address(agent.address)}"
    if tab == :overview, do: base, else: base <> "/#{tab}"
  end

  @doc "The tabs this connection's grants actually allow."
  @spec visible_tabs(map()) :: [map()]
  def visible_tabs(connection) do
    Enum.filter(@tabs, fn
      %{capability: nil} -> true
      %{capability: capability} -> Scopes.can?(connection.manifest, capability)
    end)
  end

  attr :connection, :map, required: true
  attr :agent, :any, required: true
  attr :tab, :atom, required: true

  def agent_header(assigns) do
    assigns = assign(assigns, :tabs, visible_tabs(assigns.connection))

    ~H"""
    <.header>
      {@agent.display_name}
      <:subtitle>{@agent.address}</:subtitle>
      <:actions>
        <div class="flex flex-wrap items-center gap-3">
          <.led state={Pulse.led_state(@connection.status)}>{@connection.status}</.led>
          <.button navigate={"/connections/#{@connection.id}"}>./connection</.button>
        </div>
      </:actions>
    </.header>

    <div class="mt-5">
      <.tabs>
        <:tab
          :for={tab <- @tabs}
          navigate={tab_path(@connection, @agent, tab.key)}
          selected={@tab == tab.key}
        >
          {tab.label}
        </:tab>
      </.tabs>
    </div>
    """
  end
end
