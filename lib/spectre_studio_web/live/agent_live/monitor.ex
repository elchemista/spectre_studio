defmodule SpectreStudioWeb.AgentLive.Monitor do
  @moduledoc """
  Realtime runtime monitoring for one Agent Instance.

  The lifecycle Pulse asks for in `docs/STUDIO_MONITORING.md` falls out of this
  page existing at all: monitoring starts only when the operator asks, the
  subscription id comes from the host, and leaving the panel ends this process —
  which disables the stream both here and, as a backstop, through the connection
  process watching this pid.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell
  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Pulse.Connection
  alias SpectreStudioWeb.AgentLive.Shell

  @intervals [
    {"250 ms", "250"},
    {"500 ms", "500"},
    {"1 s", "1000"},
    {"2 s", "2000"},
    {"5 s", "5000"}
  ]

  @durations [
    {"until disabled", ""},
    {"1 min", "60000"},
    {"5 min", "300000"},
    {"15 min", "900000"}
  ]

  @summary_fields ~w(memory message_queue_len reductions status total_heap_size)

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :monitor, :monitor_stream) do
      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:subscription_id, nil)
         |> assign(:subscription, nil)
         |> assign(:pending?, false)
         |> assign(:pending_request_id, nil)
         |> assign(:error, nil)
         |> assign(:fields, Connection.default_fields())
         |> assign(:summary_fields, @summary_fields)
         |> assign(:intervals, @intervals)
         |> assign(:durations, @durations)
         |> assign(:form, monitor_form())}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("enable", %{"monitor" => params}, socket) do
    subject = String.trim(params["subject"] || "")

    if subject == "" do
      {:noreply, assign(socket, :error, "a subject is required to select an Instance")}
    else
      opts = [
        agent_address: socket.assigns.agent.address,
        subject: subject,
        interval_ms: to_integer(params["interval_ms"]),
        duration_ms: to_integer(params["duration_ms"]),
        fields: socket.assigns.fields
      ]

      case Connection.enable_monitor(socket.assigns.connection.id, opts) do
        {:ok, request_id} ->
          # The subscription id only exists once the host replies. Until then the
          # control reports the request in flight — leaving it on "enable" invites
          # a second click and a second subscription for the same panel.
          {:noreply,
           socket
           |> assign(:pending?, true)
           |> assign(:pending_request_id, request_id)
           |> assign(:error, nil)
           |> assign(:form, monitor_form(params))}

        {:error, reason} ->
          {:noreply, socket |> assign(:pending?, false) |> assign(:error, describe(reason))}
      end
    end
  end

  def handle_event("disable", _params, socket), do: {:noreply, disable(socket)}

  @impl Phoenix.LiveView
  def handle_info(
        {:monitor_enabled, _id, request_id, subscription_id},
        %{assigns: %{pending_request_id: request_id}} = socket
      ) do
    {:noreply,
     assign(socket,
       subscription_id: subscription_id,
       pending?: false,
       pending_request_id: nil,
       error: nil
     )}
  end

  def handle_info({:monitor_enabled, _id, _request_id, _subscription_id}, socket),
    do: {:noreply, socket}

  def handle_info(
        {:monitor_failed, _id, request_id, error},
        %{assigns: %{pending_request_id: request_id}} = socket
      ) do
    {:noreply, assign(socket, pending?: false, pending_request_id: nil, error: describe(error))}
  end

  def handle_info({:monitor_failed, _id, _request_id, _error}, socket),
    do: {:noreply, socket}

  def handle_info({:monitor_update, _id, subscription_id, subscription}, socket) do
    if subscription_id == socket.assigns.subscription_id do
      {:noreply, assign(socket, :subscription, subscription)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:monitor_ended, _id, subscription_id}, socket) do
    if subscription_id == socket.assigns.subscription_id do
      {:noreply,
       assign(socket,
         subscription_id: nil,
         subscription: nil,
         pending?: false,
         pending_request_id: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:monitor_lost, _id, subscription_id}, socket) do
    if subscription_id == socket.assigns.subscription_id do
      # Pulse does not resume subscriptions across a reconnect, so this id is
      # dead and a fresh enable has to be an explicit act.
      {:noreply,
       socket
       |> assign(
         subscription_id: nil,
         subscription: nil,
         pending?: false,
         pending_request_id: nil
       )
       |> assign(:error, "connection lost — the subscription ended with it")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def terminate(_reason, socket) do
    # Belt and braces: the connection process also watches this pid and cleans up
    # on DOWN. Disabling here means the common case never relies on it.
    if socket.assigns[:subscription_id] do
      Connection.disable_monitor(socket.assigns.connection.id, socket.assigns.subscription_id)
    end

    :ok
  end

  defp disable(%{assigns: %{subscription_id: nil}} = socket),
    do: assign(socket, pending?: false, pending_request_id: nil)

  defp disable(socket) do
    Connection.disable_monitor(socket.assigns.connection.id, socket.assigns.subscription_id)

    assign(socket,
      subscription_id: nil,
      subscription: nil,
      pending?: false,
      pending_request_id: nil
    )
  end

  defp monitor_form(params \\ %{}) do
    to_form(
      %{
        "subject" => Map.get(params, "subject", ""),
        "interval_ms" => Map.get(params, "interval_ms", "1000"),
        "duration_ms" => Map.get(params, "duration_ms", "")
      },
      as: :monitor
    )
  end

  defp to_integer(value) when value in [nil, ""], do: nil

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> nil
    end
  end

  defp describe(:not_ready), do: "the connection is not ready"
  defp describe(:not_connected), do: "the socket is closed"
  defp describe(%{} = error), do: "#{error["kind"] || "request"}/#{error["code"] || "unknown"}"
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(reason), do: inspect(reason)

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
        <.term_window title="live" status={status_label(@subscription, @subscription_id)}>
          <div class="grid gap-5 sm:grid-cols-2 lg:grid-cols-5">
            <.metric
              :for={field <- @summary_fields}
              label={field}
              value={metric_value(@subscription, field)}
              unit={metric_unit(field)}
            />
          </div>

          <div class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
            <.spark
              :for={field <- @summary_fields}
              samples={series(@subscription, field)}
              label={"#{field} over time"}
            />
          </div>

          <div :if={mailbox(@subscription)} class="mt-6">
            <.gauge value={mailbox(@subscription)} max={64} label="mailbox" />
          </div>

          <hr class="term-rule my-6" />

          <.form for={@form} id="monitor-form" phx-submit="enable" class="grid gap-4 md:grid-cols-4">
            <div class="md:col-span-2">
              <.input field={@form[:subject]} label="subject" placeholder="account-123" />
            </div>
            <div>
              <.input field={@form[:interval_ms]} type="select" label="interval" options={@intervals} />
            </div>
            <div>
              <.input field={@form[:duration_ms]} type="select" label="duration" options={@durations} />
            </div>
            <div class="flex flex-wrap items-center gap-3 md:col-span-4">
              <.button :if={is_nil(@subscription_id) and not @pending?} variant="primary">
                enable live
              </.button>
              <.button :if={@pending?} type="button" disabled>enabling…</.button>
              <.button :if={@subscription_id} type="button" phx-click="disable">
                disable live
              </.button>
              <span :if={gaps(@subscription) > 0} class="term-comment text-[0.72rem] t-faint">
                {gaps(@subscription)} observation gaps — samples never seen, not zeroes
              </span>
            </div>
          </.form>

          <p :if={@error} class="mt-4 term-out text-[0.75rem] t-fail">{@error}</p>
          <p :if={subscription_error(@subscription)} class="mt-4 term-out text-[0.75rem] t-fail">
            {subscription_error(@subscription)}
          </p>
        </.term_window>
      </div>

      <div class="mt-6">
        <.term_window title="OTP process snapshot" status={snapshot_status(@subscription)}>
          <p :if={is_nil(@subscription)} class="text-[0.75rem] leading-6 t-dim">
            Enable live monitoring to inspect all {length(@fields)} publication-safe fields.
          </p>

          <div :if={@subscription} class="grid gap-x-8 md:grid-cols-2 xl:grid-cols-3">
            <div
              :for={{field, value} <- snapshot_rows(@subscription)}
              class="grid grid-cols-[9.5rem_1fr] gap-3 border-b border-[var(--term-border)] py-2 text-[0.7rem]"
            >
              <span class="break-all t-faint">{field}</span>
              <code class="break-all whitespace-pre-wrap t-body">{snapshot_value(value)}</code>
            </div>
          </div>

          <div :if={@subscription} class="mt-5 flex flex-wrap gap-x-6 gap-y-2 text-[0.68rem] t-faint">
            <span>subject: {@subscription.subject}</span>
            <span>sequence: {@subscription.sequence}</span>
            <span>dropped updates: {@subscription.dropped}</span>
            <span>sampled: {sampled_at(@subscription)}</span>
            <span :if={truncated_fields(@subscription) != []}>
              truncated: {Enum.join(truncated_fields(@subscription), ", ")}
            </span>
          </div>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  defp status_label(nil, nil), do: "not streaming"
  defp status_label(nil, _id), do: "waiting for first sample"

  defp status_label(subscription, _id),
    do: "seq #{subscription.sequence} · #{String.slice(subscription.id, 0, 8)}…"

  defp metric_value(nil, _field), do: nil

  defp metric_value(subscription, field) do
    case Map.get(subscription.latest, field) do
      nil -> nil
      value when field == "memory" -> format_bytes(value)
      value when is_integer(value) -> format_number(value)
      value when is_binary(value) -> value
      value -> inspect(value)
    end
  end

  defp metric_unit("total_heap_size"), do: "words"
  defp metric_unit(_field), do: nil

  defp series(nil, _field), do: []
  defp series(subscription, field), do: Map.get(subscription.series, field, [])

  defp gaps(nil), do: 0
  defp gaps(subscription), do: subscription.gaps

  defp mailbox(nil), do: nil
  defp mailbox(subscription), do: Map.get(subscription.latest, "message_queue_len")

  defp subscription_error(%{status: {:error, label}}), do: "monitor.error #{label}"
  defp subscription_error(%{status: :expired}), do: "subscription expired — enable it again"
  defp subscription_error(_subscription), do: nil

  defp snapshot_rows(subscription), do: Enum.sort_by(subscription.latest, &elem(&1, 0))

  defp snapshot_value(nil), do: "—"
  defp snapshot_value(value) when is_binary(value), do: value
  defp snapshot_value(value), do: inspect(value, pretty: true, limit: 50)

  defp snapshot_status(nil), do: "not sampled"
  defp snapshot_status(subscription), do: "#{map_size(subscription.latest)} fields"

  defp sampled_at(subscription) do
    case Map.get(subscription.snapshot, "sampled_at_unix_ms") do
      value when is_integer(value) ->
        value |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%H:%M:%S.%f")

      _other ->
        "—"
    end
  end

  defp truncated_fields(subscription) do
    case Map.get(subscription.snapshot, "truncated_fields", []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: :erlang.float_to_binary(bytes / 1_048_576, decimals: 1) <> " MB"

  defp format_bytes(bytes) when bytes >= 1024,
    do: :erlang.float_to_binary(bytes / 1024, decimals: 1) <> " kB"

  defp format_bytes(bytes), do: "#{bytes} B"

  defp format_number(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(" ", &Enum.join/1)
    |> String.reverse()
  end
end
