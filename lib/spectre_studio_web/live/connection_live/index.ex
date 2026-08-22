defmodule SpectreStudioWeb.ConnectionLive.Index do
  @moduledoc """
  The dashboard: every configured Pulse endpoint and what it is doing.

  The endpoints are a stream. A connection changing state sends one update for
  one card, rather than re-rendering the whole grid every time a socket
  reconnects somewhere.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Pulse
  alias SpectreStudio.Pulse.Events
  alias SpectreStudioWeb.Nav

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    endpoints = Pulse.list()

    if connected?(socket) do
      Enum.each(endpoints, &Events.subscribe(Events.connection_topic(&1.id)))
    end

    {:ok,
     socket
     |> assign(:page_title, "connections")
     |> assign(:active_section, :connections)
     |> assign(:endpoint_count, length(endpoints))
     |> stream(:endpoints, endpoints)}
  end

  @impl Phoenix.LiveView
  def handle_event("connect", %{"id" => id}, socket) do
    Pulse.connect(id)
    {:noreply, refresh(socket, id)}
  end

  def handle_event("disconnect", %{"id" => id}, socket) do
    Pulse.disconnect(id)
    {:noreply, refresh(socket, id)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    :ok = Pulse.delete(id)

    {:noreply,
     socket
     |> put_flash(:info, "Connection removed.")
     |> stream_delete_by_dom_id(:endpoints, "endpoints-#{id}")
     |> update(:endpoint_count, &max(&1 - 1, 0))
     # The rail is normally refreshed by the directory broadcast, which arrives
     # after this event has rendered. Doing it here means the removal is visible
     # everywhere in the same frame the operator caused it.
     |> assign(:connections, Nav.rail_entries())}
  end

  @impl Phoenix.LiveView
  def handle_info({:connection_status, id, _status}, socket), do: {:noreply, refresh(socket, id)}

  def handle_info(:directory_changed, socket) do
    # A connection was added or removed elsewhere. Only the set can change here,
    # so the stream is reset rather than patched entry by entry.
    endpoints = Pulse.list()

    if connected?(socket) do
      Enum.each(endpoints, &Events.subscribe(Events.connection_topic(&1.id)))
    end

    {:noreply,
     socket
     |> assign(:endpoint_count, length(endpoints))
     |> stream(:endpoints, endpoints, reset: true)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh(socket, id) do
    case Pulse.fetch(id) do
      {:ok, endpoint} -> stream_insert(socket, :endpoints, endpoint)
      :error -> socket
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} connections={@connections} active_section={@active_section}>
      <.header>
        connections
        <:subtitle>every Spectre system this Studio can reach</:subtitle>
        <:actions>
          <.link navigate={~p"/connections/new"} class="term-btn term-btn--primary">
            ./new-connection
          </.link>
        </:actions>
      </.header>

      <div :if={@endpoint_count == 0} class="mt-10 space-y-3">
        <p class="term-comment text-[0.8rem] t-faint">no connections configured</p>
        <p class="term-prompt text-[0.8rem] t-dim">./new-connection</p>
      </div>

      <div
        id="endpoints"
        phx-update="stream"
        class="mt-6 grid gap-5 lg:grid-cols-2 xl:grid-cols-3"
      >
        <article
          :for={{dom_id, endpoint} <- @streams.endpoints}
          id={dom_id}
          class="term-window term-window--link overflow-hidden"
        >
          <div class="term-bar">
            <span class="term-dots" aria-hidden="true">
              <span class="term-dot"></span>
              <span class="term-dot"></span>
              <span class="term-dot"></span>
            </span>
            <span class="term-title">{endpoint.label}</span>
            <span class="ml-auto flex-none t-faint">{scheme(endpoint.display_url)}</span>
          </div>
          <div class="term-body space-y-4">
            <.led state={Pulse.led_state(endpoint.status)}>{endpoint.status}</.led>

            <.list>
              <:item title="endpoint">{endpoint.display_url}</:item>
              <:item title="agents">{agent_count(endpoint)}</:item>
              <:item title="tls">
                {if endpoint.spec.verify_tls, do: "verified", else: "UNVERIFIED"}
              </:item>
            </.list>

            <p :if={endpoint.last_error} class="term-out text-[0.72rem] t-fail">
              {endpoint.last_error}
            </p>

            <div class="flex flex-wrap gap-2">
              <.button navigate={~p"/connections/#{endpoint.id}"}>open</.button>
              <.button
                :if={endpoint.status not in [:ready, :connecting, :authenticating]}
                variant="primary"
                phx-click="connect"
                phx-value-id={endpoint.id}
              >
                connect
              </.button>
              <.button
                :if={endpoint.status in [:ready, :connecting, :authenticating, :degraded]}
                phx-click="disconnect"
                phx-value-id={endpoint.id}
              >
                disconnect
              </.button>
              <.button navigate={~p"/connections/#{endpoint.id}/edit"}>edit</.button>
              <.button
                phx-click="delete"
                phx-value-id={endpoint.id}
                data-confirm={"Remove #{endpoint.label}?"}
                class="term-btn border-transparent t-dim hover:t-strong"
              >
                remove
              </.button>
            </div>
          </div>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp agent_count(%{manifest: nil}), do: "—"
  defp agent_count(%{manifest: manifest}), do: length(manifest.agents)

  defp scheme(url), do: url |> String.split("://") |> List.first()
end
