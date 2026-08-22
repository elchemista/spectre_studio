defmodule SpectreStudioWeb.AgentLive.Overview do
  @moduledoc """
  What Studio knows about one Agent without asking the host for anything.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell
  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Pulse.Scopes
  alias SpectreStudioWeb.AgentLive.Shell

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :overview) do
      {:ok, socket} -> {:ok, assign(socket, :withheld, withheld(socket))}
      {:redirect, socket} -> {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp withheld(socket), do: Scopes.partition(socket.assigns.connection.manifest).withheld

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

      <div class="mt-6 grid gap-6 xl:grid-cols-2">
        <.term_window title="identity">
          <.list>
            <:item title="address">{@agent.address}</:item>
            <:item title="display name">{@agent.display_name}</:item>
            <:item title="capabilities">{join_or_dash(@agent.capabilities)}</:item>
            <:item title="protocol">
              <span class="tabular">{join_or_dash(@agent.protocol_versions)}</span>
            </:item>
          </.list>
        </.term_window>

        <.term_window title="what this panel can show">
          <p class="text-[0.78rem] leading-6 t-body">
            Runtime monitoring samples selected <span class="t-strong">Process.info/2</span>
            fields from the OTP process behind one Agent Instance. It is not the Agent's history.
          </p>

          <div :if={@withheld != []} class="mt-5 space-y-2">
            <p class="term-label">panels withheld by this connection</p>
            <div class="flex flex-wrap gap-2">
              <.scope_badge :for={scope <- @withheld} scope={scope} granted={false} />
            </div>
          </div>

          <ul class="mt-5 space-y-2 text-[0.75rem] leading-6 t-dim">
            <li class="flex gap-3">
              <span class="flex-none t-faint" aria-hidden="true">-</span>
              <span>no mailbox contents, process dictionary or GenServer state</span>
            </li>
            <li class="flex gap-3">
              <span class="flex-none t-faint" aria-hidden="true">-</span>
              <span>no memory records, prompts or model calls</span>
            </li>
            <li class="flex gap-3">
              <span class="flex-none t-faint" aria-hidden="true">-</span>
              <span>token totals belong to Ledger, not to this stream</span>
            </li>
          </ul>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  defp join_or_dash([]), do: "—"
  defp join_or_dash(values), do: Enum.join(values, ", ")
end
