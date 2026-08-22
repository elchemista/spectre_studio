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
    %{key: :operations, label: "work / vigil", capability: :operations_stream},
    %{
      key: :cache,
      label: "semantic cache",
      capability: {:any, [:semantic_cache_read, :semantic_cache_promote]}
    },
    %{key: :journal, label: "journal / turns", capability: :ledger_read},
    %{
      key: :evolve,
      label: "skills / morph",
      capability: {:any, [:skill_read, :morph_create]}
    },
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

  @doc "Loads one Agent panel and requires its declared Studio capability."
  @spec mount_agent(LiveView.Socket.t(), map(), atom(), Scopes.capability() | {:any, list()}) ::
          {:ok, LiveView.Socket.t()} | {:redirect, LiveView.Socket.t()}
  def mount_agent(socket, params, tab, requirement) do
    case mount_agent(socket, params, tab) do
      {:ok, socket} ->
        if permitted?(socket.assigns.connection.manifest, requirement) do
          {:ok, socket}
        else
          id = socket.assigns.connection.id
          {:redirect, redirect_to(socket, id, "This connection does not grant that panel.")}
        end

      {:redirect, socket} ->
        {:redirect, socket}
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

  @doc "All known Agent tabs annotated with their current availability."
  @spec visible_tabs(map()) :: [map()]
  def visible_tabs(connection) do
    Enum.map(@tabs, fn tab ->
      available? = is_nil(tab.capability) or permitted?(connection.manifest, tab.capability)

      tab
      |> Map.put(:available?, available?)
      |> Map.put(:missing_scopes, missing_scopes(connection.manifest, tab.capability))
    end)
  end

  @spec missing_scopes(Manifest.t() | nil, nil | Scopes.capability() | {:any, list()}) ::
          [String.t()]
  defp missing_scopes(_manifest, nil), do: []

  defp missing_scopes(manifest, {:any, capabilities}) do
    if Scopes.any?(manifest, capabilities) do
      []
    else
      capabilities |> Enum.flat_map(&Scopes.required_scopes/1) |> Enum.uniq()
    end
  end

  defp missing_scopes(manifest, capability) do
    if Scopes.can?(manifest, capability), do: [], else: Scopes.required_scopes(capability)
  end

  @spec permitted?(Manifest.t() | nil, Scopes.capability() | {:any, [Scopes.capability()]}) ::
          boolean()
  defp permitted?(manifest, {:any, capabilities}), do: Scopes.any?(manifest, capabilities)
  defp permitted?(manifest, capability), do: Scopes.can?(manifest, capability)

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
          disabled={!tab.available?}
          title={missing_title(tab.missing_scopes)}
        >
          {tab.label}
        </:tab>
      </.tabs>
    </div>
    """
  end

  @spec missing_title([String.t()]) :: String.t() | nil
  defp missing_title([]), do: nil
  defp missing_title(scopes), do: "not granted: " <> Enum.join(scopes, ", ")
end
