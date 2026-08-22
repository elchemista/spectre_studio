defmodule SpectreStudioWeb.AgentLive.Overview do
  @moduledoc """
  What Studio knows about one Agent without asking the host for anything.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell
  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Pulse.Scopes
  alias SpectreStudioWeb.AgentLive.Shell

  @capabilities [
    {:monitor_stream, "OTP process info", "safe Process.info/2 snapshots and live series"},
    {:operations_stream, "Work / Vigil", "bounded operation snapshots and lifecycle state"},
    {:semantic_cache_read, "Semantic cache · inspect", "review cache examples"},
    {:semantic_cache_promote, "Semantic cache · verify", "promote one reviewed example"},
    {:ledger_read, "Journal / turns", "load persisted conversation turn history"},
    {:skill_read, "Skill inventory", "list compiled and governed Skill mounts"},
    {:skill_create, "Skill runtime mount", "host-owned direct runtime mutation authority"},
    {:morph_create, "Morph", "evaluate a runtime Skill proposal"},
    {:message_send, "Messages", "send an application envelope to this Agent"},
    {:control, "Agent control", "invoke host-defined lifecycle controls"},
    {:lab_read, "Lab", "read host-defined evaluation data"}
  ]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :overview) do
      {:ok, socket} ->
        scopes = Scopes.partition(socket.assigns.connection.manifest)

        {:ok,
         socket
         |> assign(:granted, scopes.granted)
         |> assign(:withheld, scopes.withheld)
         |> assign(:capability_matrix, capability_matrix(socket))}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp capability_matrix(socket) do
    manifest = socket.assigns.connection.manifest

    Enum.map(@capabilities, fn {capability, label, description} ->
      required = Scopes.required_scopes(capability)

      %{
        label: label,
        description: description,
        available?: Scopes.can?(manifest, capability),
        required: required,
        missing: Enum.reject(required, &(&1 in manifest.granted_scopes))
      }
    end)
  end

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
            <:item title="principal">{@connection.manifest.principal_identity || "—"}</:item>
            <:item title="peer">{@connection.manifest.peer_id || "—"}</:item>
          </.list>

          <p :if={@agent.capabilities == []} class="mt-5 term-out text-[0.75rem] t-warn">
            The remote manifest advertises no Agent capabilities. Studio cannot infer them from
            the address.
          </p>
        </.term_window>

        <.term_window title="connection authority">
          <p class="text-[0.78rem] leading-6 t-body">
            Profile
            <span class="t-strong">{join_or_dash(@connection.manifest.granted_profiles)}</span>
            · mode <span class="t-strong">{@connection.manifest.spec_mode || "—"}</span>. Grants are
            enforced by Pulse; a visible locked panel is not callable.
          </p>

          <div class="mt-5 space-y-2">
            <p class="term-label">granted scopes</p>
            <div class="flex flex-wrap gap-2">
              <.scope_badge :for={scope <- @granted} scope={scope} />
              <span :if={@granted == []} class="text-[0.75rem] t-faint">none</span>
            </div>
          </div>

          <div :if={@withheld != []} class="mt-5 space-y-2">
            <p class="term-label">panels withheld by this connection</p>
            <div class="flex flex-wrap gap-2">
              <.scope_badge :for={scope <- @withheld} scope={scope} granted={false} />
            </div>
          </div>
        </.term_window>
      </div>

      <div class="mt-6">
        <.term_window title="capability matrix" status={matrix_status(@capability_matrix)}>
          <div class="divide-y divide-[var(--term-border)]">
            <div
              :for={capability <- @capability_matrix}
              class="grid gap-2 py-4 first:pt-0 last:pb-0 md:grid-cols-[13rem_1fr_auto] md:items-start"
            >
              <div>
                <span class={[
                  "mr-2",
                  capability.available? && "t-success",
                  !capability.available? && "t-fail"
                ]}>
                  {if capability.available?, do: "●", else: "○"}
                </span>
                <span class="text-[0.78rem] t-strong">{capability.label}</span>
              </div>
              <div>
                <p class="text-[0.75rem] leading-5 t-dim">{capability.description}</p>
                <p :if={!capability.available?} class="mt-1 text-[0.68rem] t-faint">
                  missing: {Enum.join(capability.missing, ", ")}
                </p>
              </div>
              <span class={[
                "term-chip justify-self-start",
                !capability.available? && "term-chip--withheld"
              ]}>
                {if capability.available?, do: "ready", else: "locked"}
              </span>
            </div>
          </div>
        </.term_window>
      </div>

      <div class="mt-6">
        <.term_window title="inspection boundaries">
          <p class="text-[0.75rem] leading-6 t-dim">
            OTP monitoring exposes only Pulse's bounded safe field allowlist: no mailbox contents,
            process dictionary, GenServer state, prompts or model calls. Journal turns
            come separately through <span class="t-strong">ledger.read</span>; semantic examples
            come through <span class="t-strong">agent.semantic_cache.read</span>. Token totals
            belong to Ledger, not to the OTP stream.
          </p>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  defp join_or_dash([]), do: "—"
  defp join_or_dash(values), do: Enum.join(values, ", ")

  defp matrix_status(capabilities) do
    ready = Enum.count(capabilities, & &1.available?)
    "#{ready}/#{length(capabilities)} ready"
  end
end
