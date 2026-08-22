defmodule SpectreStudioWeb.AgentLive.Operations do
  @moduledoc """
  Temporary Work and Vigil monitoring for one Agent Instance.

  Pulse publishes complete bounded `Spectre.Operation.View` snapshots. This
  panel replaces its projection on every sample; it does not invent a durable
  operation history from an observation stream.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell
  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Pulse.Connection
  alias SpectreStudioWeb.AgentLive.Shell

  @intervals [{"250 ms", "250"}, {"1 s", "1000"}, {"5 s", "5000"}, {"30 s", "30000"}]
  @durations [{"until stopped", ""}, {"1 min", "60000"}, {"5 min", "300000"}]
  @kind_options [{"Work + Vigil", "all"}, {"Work", "work"}, {"Vigil", "vigil"}]

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :operations, :operations_stream) do
      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:subscription_id, nil)
         |> assign(:subscription, nil)
         |> assign(:pending?, false)
         |> assign(:error, nil)
         |> assign(:intervals, @intervals)
         |> assign(:durations, @durations)
         |> assign(:kind_options, @kind_options)
         |> assign(:form, operations_form())}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("enable", %{"operations" => params}, socket) do
    subject = String.trim(params["subject"] || "")

    if subject == "" do
      {:noreply, assign(socket, :error, "a subject is required to select an Instance")}
    else
      opts = [
        agent_address: socket.assigns.agent.address,
        subject: subject,
        interval_ms: to_integer(params["interval_ms"]),
        duration_ms: to_integer(params["duration_ms"]),
        kinds: kinds(params["kinds"]),
        include_terminal: params["include_terminal"] == "true"
      ]

      case Connection.enable_operations_monitor(socket.assigns.connection.id, opts) do
        {:ok, _request_id} ->
          {:noreply,
           socket
           |> assign(:pending?, true)
           |> assign(:error, nil)
           |> assign(:form, operations_form(params))}

        {:error, reason} ->
          {:noreply, socket |> assign(:pending?, false) |> assign(:error, describe(reason))}
      end
    end
  end

  def handle_event("disable", _params, socket), do: {:noreply, disable(socket)}

  @impl Phoenix.LiveView
  def handle_info({:operations_monitor_enabled, _id, _request_id, subscription_id}, socket) do
    {:noreply, assign(socket, subscription_id: subscription_id, pending?: false, error: nil)}
  end

  def handle_info({:operations_monitor_update, _id, subscription_id, subscription}, socket) do
    if subscription_id == socket.assigns.subscription_id do
      {:noreply, assign(socket, :subscription, subscription)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:operations_monitor_ended, _id, subscription_id}, socket) do
    {:noreply, clear_if_current(socket, subscription_id)}
  end

  def handle_info({:operations_monitor_lost, _id, subscription_id}, socket) do
    if subscription_id == socket.assigns.subscription_id do
      {:noreply,
       socket
       |> clear_subscription()
       |> assign(:error, "connection lost — the Work/Vigil subscription ended with it")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def terminate(_reason, socket) do
    if socket.assigns[:subscription_id] do
      Connection.disable_monitor(socket.assigns.connection.id, socket.assigns.subscription_id)
    end

    :ok
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

      <div class="mt-6 space-y-6">
        <.term_window title="Work / Vigil" status={status_label(@subscription, @subscription_id)}>
          <div class="grid gap-5 sm:grid-cols-3">
            <.metric label="total" value={count(@subscription, "total")} />
            <.metric label="work" value={count(@subscription, "work")} />
            <.metric label="vigil" value={count(@subscription, "vigil")} />
          </div>

          <p class="mt-5 text-[0.75rem] leading-6 t-dim">
            Each update is a publication-safe bounded snapshot, not durable history.
            Redacted fields remain redacted and sequence gaps are observation gaps.
          </p>

          <hr class="term-rule my-6" />

          <.form
            for={@form}
            id="operations-form"
            phx-submit="enable"
            class="grid gap-4 md:grid-cols-4"
          >
            <div>
              <.input field={@form[:subject]} label="subject" placeholder="account-123" />
            </div>
            <div>
              <.input field={@form[:kinds]} type="select" label="loops" options={@kind_options} />
            </div>
            <div>
              <.input field={@form[:interval_ms]} type="select" label="interval" options={@intervals} />
            </div>
            <div>
              <.input field={@form[:duration_ms]} type="select" label="duration" options={@durations} />
            </div>
            <div class="md:col-span-4">
              <.input field={@form[:include_terminal]} type="checkbox" label="include terminal loops" />
            </div>
            <div class="flex flex-wrap items-center gap-3 md:col-span-4">
              <.button :if={is_nil(@subscription_id) and not @pending?} variant="primary">
                watch Work / Vigil
              </.button>
              <.button :if={@pending?} type="button" disabled>enabling…</.button>
              <.button :if={@subscription_id} type="button" phx-click="disable">stop watching</.button>
              <span :if={gaps(@subscription) > 0} class="term-comment text-[0.72rem] t-faint">
                {gaps(@subscription)} observation gaps
              </span>
            </div>
          </.form>

          <p :if={@error} class="mt-4 term-out text-[0.75rem] t-fail">{@error}</p>
        </.term_window>

        <.term_window title="active loops" status={"#{length(operations(@subscription))}"}>
          <p :if={operations(@subscription) == []} class="term-comment text-[0.78rem] t-faint">
            no operation snapshot yet
          </p>

          <div class="space-y-4">
            <article
              :for={operation <- operations(@subscription)}
              id={"operation-#{operation["id"]}"}
              class="border border-[var(--border)] p-4"
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p class="term-label">{operation["kind"]} · {operation["definition"]}</p>
                  <p class="mt-1 text-[0.72rem] t-faint">{operation["id"]}</p>
                </div>
                <.led state={operation_led(operation["status"])}>
                  {operation["status"] || "unknown"}
                </.led>
              </div>
              <dl class="mt-4 grid gap-3 text-[0.75rem] sm:grid-cols-3">
                <div>
                  <dt class="t-faint">phase</dt><dd class="t-body">{operation["phase"] || "—"}</dd>
                </div>
                <div>
                  <dt class="t-faint">operation</dt><dd class="t-body">
                    {operation["operation"] || "—"}
                  </dd>
                </div>
                <div>
                  <dt class="t-faint">retries</dt><dd class="t-body">{operation["retries"] || 0}</dd>
                </div>
              </dl>
              <pre :if={operation["progress"]} class="term-code mt-4 overflow-auto">{json(operation["progress"])}</pre>
            </article>
          </div>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  @spec disable(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp disable(%{assigns: %{subscription_id: nil}} = socket), do: assign(socket, :pending?, false)

  defp disable(socket) do
    Connection.disable_monitor(socket.assigns.connection.id, socket.assigns.subscription_id)
    clear_subscription(socket)
  end

  @spec clear_if_current(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp clear_if_current(socket, subscription_id) do
    if subscription_id == socket.assigns.subscription_id,
      do: clear_subscription(socket),
      else: socket
  end

  @spec clear_subscription(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp clear_subscription(socket) do
    assign(socket, subscription_id: nil, subscription: nil, pending?: false)
  end

  @spec operations_form(map()) :: Phoenix.HTML.Form.t()
  defp operations_form(params \\ %{}) do
    to_form(
      %{
        "subject" => Map.get(params, "subject", ""),
        "kinds" => Map.get(params, "kinds", "all"),
        "interval_ms" => Map.get(params, "interval_ms", "1000"),
        "duration_ms" => Map.get(params, "duration_ms", ""),
        "include_terminal" => Map.get(params, "include_terminal", "false")
      },
      as: :operations
    )
  end

  @spec kinds(String.t() | nil) :: [String.t()]
  defp kinds("work"), do: ["work"]
  defp kinds("vigil"), do: ["vigil"]
  defp kinds(_value), do: ["work", "vigil"]

  @spec to_integer(String.t() | nil) :: integer() | nil
  defp to_integer(value) when value in [nil, ""], do: nil

  defp to_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _invalid -> nil
    end
  end

  @spec operations(map() | nil) :: [map()]
  defp operations(nil), do: []
  defp operations(subscription), do: Map.get(subscription.snapshot, "operations", [])

  @spec count(map() | nil, String.t()) :: non_neg_integer()
  defp count(nil, _kind), do: 0
  defp count(subscription, kind), do: get_in(subscription.snapshot, ["counts", kind]) || 0

  @spec gaps(map() | nil) :: non_neg_integer()
  defp gaps(nil), do: 0
  defp gaps(subscription), do: subscription.gaps

  @spec status_label(map() | nil, String.t() | nil) :: String.t()
  defp status_label(nil, nil), do: "not streaming"
  defp status_label(nil, _id), do: "waiting for first snapshot"
  defp status_label(subscription, _id), do: "seq #{subscription.sequence}"

  @spec operation_led(String.t() | nil) :: :ok | :wait | :fail | :idle
  defp operation_led(status) when status in ["running", "active"], do: :ok
  defp operation_led(status) when status in ["waiting", "paused", "blocked"], do: :wait
  defp operation_led(status) when status in ["failed", "stopped"], do: :fail
  defp operation_led(_status), do: :idle

  @spec json(term()) :: String.t()
  defp json(value), do: Jason.encode!(value, pretty: true)

  @spec describe(term()) :: String.t()
  defp describe(:not_ready), do: "the connection is not ready"
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(reason), do: inspect(reason)
end
