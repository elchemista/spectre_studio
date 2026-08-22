defmodule SpectreStudio.Pulse.Connection do
  @moduledoc """
  Owns one live connection to a Pulse endpoint.

  This process is the only thing in Studio that knows a socket exists. It holds
  the connection state machine, the manifest, the monitoring subscriptions and
  their sample buffers, and it publishes what changed. LiveViews read from here
  and never the other way round, so a dozen open tabs still produce one socket,
  one subscription and one series.

  It also mirrors, on the Studio side, the cleanup guarantee Pulse gives on the
  host side: a monitoring subscription is owned by the LiveView that asked for
  it, and when that process dies the subscription is disabled. Neither end
  leaves a stream running for a reader who is gone.

  State machine, all of it visible in the UI:

      :idle → :connecting → :authenticating → :ready
                  ↑              ↓               ↓
                  └── :degraded ←┴───────────────┘
                        ↓
                     :closed | :error
  """

  use GenServer

  alias SpectreStudio.Pulse.ConnectionSpec
  alias SpectreStudio.Pulse.Events
  alias SpectreStudio.Pulse.Frame
  alias SpectreStudio.Pulse.Manifest
  alias SpectreStudio.Pulse.Socket

  @registry SpectreStudio.Pulse.Registry
  @series_length 120
  @event_log_length 200
  @max_backoff_ms 30_000
  @default_fields ~w(memory message_queue_len reductions status total_heap_size)

  @doc "The safe process fields Studio offers, a subset of the Pulse vocabulary."
  @spec default_fields() :: [String.t()]
  def default_fields, do: @default_fields

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    spec = Keyword.fetch!(opts, :spec)
    GenServer.start_link(__MODULE__, opts, name: via(spec.id))
  end

  @doc false
  @spec via(String.t()) :: {:via, Registry, {atom(), String.t()}}
  def via(id), do: {:via, Registry, {@registry, id}}

  @doc "Whether a connection process is running for this spec."
  @spec alive?(String.t()) :: boolean()
  def alive?(id), do: Registry.lookup(@registry, id) != []

  @doc "Asks the connection to open its socket."
  @spec connect(String.t()) :: :ok | {:error, :not_running}
  def connect(id), do: cast(id, :connect)

  @doc "Closes the socket and stops reconnecting until asked again."
  @spec disconnect(String.t()) :: :ok | {:error, :not_running}
  def disconnect(id), do: cast(id, :disconnect)

  @doc "Reads the current public state."
  @spec snapshot(String.t()) :: {:ok, map()} | {:error, :not_running}
  def snapshot(id), do: call(id, :snapshot)

  @doc """
  Enables realtime monitoring for one Agent Instance.

  `:owner` is the process that will receive the stream; its death disables the
  subscription. Studio supplies a `request_id` and takes the `subscription_id`
  from the reply — subscription ids are the server's to mint.
  """
  @spec enable_monitor(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def enable_monitor(id, opts), do: call(id, {:enable_monitor, opts, self()})

  @doc "Disables one subscription."
  @spec disable_monitor(String.t(), String.t()) :: :ok | {:error, term()}
  def disable_monitor(id, subscription_id), do: call(id, {:disable_monitor, subscription_id})

  @doc "Sends one Pulse envelope to an Agent."
  @spec send_envelope(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def send_envelope(id, opts), do: call(id, {:send_envelope, opts})

  defp call(id, message) do
    GenServer.call(via(id), message, 10_000)
  catch
    :exit, _reason -> {:error, :not_running}
  end

  defp cast(id, message) do
    GenServer.cast(via(id), message)
  catch
    :exit, _reason -> {:error, :not_running}
  end

  # --- server ----------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    spec = Keyword.fetch!(opts, :spec)

    state = %{
      spec: spec,
      status: :idle,
      socket: nil,
      manifest: nil,
      last_error: nil,
      attempt: 0,
      reconnect_ref: nil,
      subscriptions: %{},
      pending: %{},
      owners: %{},
      sent: %{},
      events: [],
      event_seq: 0
    }

    if spec.auto_connect, do: send(self(), :connect)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast(:connect, state), do: {:noreply, open(state)}

  def handle_cast(:disconnect, state) do
    state =
      state
      |> cancel_reconnect()
      |> close_socket()
      |> log(:sent, "disconnect requested")
      |> transition(:closed)

    {:noreply, %{state | attempt: 0, manifest: nil, subscriptions: %{}, pending: %{}}}
  end

  @impl GenServer
  def handle_call(:snapshot, _from, state), do: {:reply, {:ok, public(state)}, state}

  def handle_call({:enable_monitor, opts, owner}, _from, state) do
    if state.status == :ready do
      do_enable_monitor(opts, owner, state)
    else
      {:reply, {:error, :not_ready}, state}
    end
  end

  def handle_call({:disable_monitor, subscription_id}, _from, state) do
    case Map.fetch(state.subscriptions, subscription_id) do
      {:ok, _subscription} ->
        {:ok, frame} = Frame.monitor_disable(subscription_id)
        push(state, frame)

        {:reply, :ok,
         state
         |> log(:sent, "monitor.disable #{short(subscription_id)}")
         |> drop_subscription(subscription_id)}

      :error ->
        {:reply, {:error, :unknown_subscription}, state}
    end
  end

  def handle_call({:send_envelope, opts}, _from, state) do
    with :ready <- state.status,
         {:ok, from} <- studio_identity(state),
         {:ok, frame, envelope} <- Frame.envelope(Keyword.put(opts, :from, from)),
         :ok <- push(state, frame) do
      state =
        state
        |> log(:sent, "#{envelope["act"]} → #{envelope["to"]} · #{envelope["payload"]["type"]}")
        |> track_sent(envelope)

      {:reply, {:ok, envelope}, state}
    else
      status when is_atom(status) -> {:reply, {:error, :not_ready}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info(:connect, state), do: {:noreply, open(state)}

  def handle_info(:reconnect, state), do: {:noreply, open(%{state | reconnect_ref: nil})}

  def handle_info({:pulse_socket, socket, :open}, %{socket: socket} = state) do
    {:noreply,
     state
     |> log(:received, "socket open, awaiting manifest")
     |> transition(:authenticating)}
  end

  def handle_info({:pulse_socket, socket, {:frame, text}}, %{socket: socket} = state) do
    {:noreply, handle_frame(text, state)}
  end

  def handle_info({:DOWN, _ref, :process, socket, reason}, %{socket: socket} = state) do
    {:noreply, socket_down(reason, %{state | socket: nil})}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # A panel went away. Disable everything it was watching, so the host does
    # not keep sampling a process for a reader that no longer exists.
    {:noreply, disable_owned_by(pid, state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # --- connecting ------------------------------------------------------------

  defp open(%{status: :ready} = state), do: state
  defp open(%{socket: socket} = state) when is_pid(socket), do: state

  defp open(state) do
    opts = [
      owner: self(),
      url: state.spec.url,
      token: state.spec.token,
      verify_tls: state.spec.verify_tls
    ]

    case Socket.start(opts) do
      {:ok, socket} ->
        Process.monitor(socket)

        state
        |> log(:sent, "connecting to #{ConnectionSpec.display_url(state.spec)}")
        |> Map.put(:socket, socket)
        |> transition(:connecting)

      {:error, {:shutdown, reason}} ->
        fail(state, reason)

      {:error, reason} ->
        fail(state, reason)
    end
  end

  defp socket_down(reason, state) do
    reason = normalize_reason(reason)

    # Every subscription id issued over that socket is dead with it. Pulse does
    # not resume them, so Studio must not pretend otherwise: the panels are told
    # the stream ended and a fresh enable is an explicit act.
    state =
      state
      |> notify_subscriptions_lost()
      |> Map.put(:subscriptions, %{})
      |> Map.put(:pending, %{})
      |> Map.put(:manifest, nil)

    case {state.status, terminal?(reason)} do
      {:closed, _terminal} ->
        state

      {_status, true} ->
        state
        |> log(:fail, "connection refused: #{describe(reason)}")
        |> Map.put(:last_error, describe(reason))
        |> transition(:error)

      {_status, false} ->
        state
        |> log(:fail, "connection lost: #{describe(reason)}")
        |> Map.put(:last_error, describe(reason))
        |> transition(:degraded)
        |> schedule_reconnect()
    end
  end

  defp fail(state, reason) do
    state
    |> log(:fail, "connect failed: #{describe(reason)}")
    |> Map.put(:last_error, describe(reason))
    |> transition(if terminal?(reason), do: :error, else: :degraded)
    |> then(fn state -> if terminal?(reason), do: state, else: schedule_reconnect(state) end)
  end

  # An unauthorised connection is not a transient failure. Retrying it forever
  # would hammer the host with a credential it has already rejected.
  defp terminal?(:unauthorized), do: true
  defp terminal?(:invalid_url), do: true
  defp terminal?({:upgrade_failed, status}) when status in 400..499, do: true
  defp terminal?(_reason), do: false

  defp schedule_reconnect(state) do
    attempt = state.attempt + 1
    base = min(trunc(:math.pow(2, min(attempt, 5))) * 1_000, @max_backoff_ms)
    delay = base + :rand.uniform(500)
    ref = Process.send_after(self(), :reconnect, delay)

    log(
      %{state | attempt: attempt, reconnect_ref: ref},
      :note,
      "retrying in #{div(delay, 1000)}s"
    )
  end

  defp cancel_reconnect(%{reconnect_ref: nil} = state), do: state

  defp cancel_reconnect(%{reconnect_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | reconnect_ref: nil}
  end

  defp close_socket(%{socket: nil} = state), do: state

  defp close_socket(%{socket: socket} = state) do
    Socket.close(socket)
    %{state | socket: nil}
  end

  # --- frames ----------------------------------------------------------------

  defp handle_frame(text, state) do
    case Frame.decode(text) do
      {:ok, {:manifest, frame}} -> apply_manifest(frame, state)
      {:ok, {:receipt, receipt}} -> apply_receipt(receipt, state)
      {:ok, {:error, error}} -> apply_error(error, state)
      {:ok, {:monitor, event, frame}} -> apply_monitor(event, frame, state)
      {:ok, {:envelope, envelope}} -> apply_envelope(envelope, state)
      {:ok, {:unknown, _frame}} -> log(state, :note, "unrecognised frame ignored")
      {:error, reason} -> log(state, :fail, "undecodable frame: #{reason}")
    end
  end

  defp apply_manifest(frame, state) do
    case Manifest.normalize(frame) do
      {:ok, manifest} ->
        %{state | manifest: manifest, attempt: 0, last_error: nil}
        |> log(
          :received,
          "manifest: #{length(manifest.agents)} agents, #{length(manifest.granted_scopes)} scopes"
        )
        |> transition(:ready)

      {:error, _reason} ->
        log(state, :fail, "manifest rejected: unexpected shape")
    end
  end

  defp apply_receipt(receipt, state) do
    id = Map.get(receipt, "message_id")
    status = Map.get(receipt, "status", "accepted")

    state
    |> put_receipt(id, receipt)
    |> log(:received, "receipt #{status} #{short(id)}")
  end

  defp apply_error(error, state) do
    code = Map.get(error, "code", "unknown")
    kind = Map.get(error, "kind", "request")

    state
    |> Map.put(:last_error, "#{kind}/#{code}")
    |> log(:fail, "error #{kind}/#{code}")
  end

  defp apply_envelope(envelope, state) do
    from = Map.get(envelope, "from", "unknown")
    type = get_in(envelope, ["payload", "type"]) || "unknown"

    broadcast(state, {:envelope, state.spec.id, envelope})
    log(state, :received, "#{from} · #{type}")
  end

  # --- monitoring ------------------------------------------------------------

  defp do_enable_monitor(opts, owner, state) do
    request_id = Frame.uuid7()

    frame_opts = [
      request_id: request_id,
      agent_address: Keyword.fetch!(opts, :agent_address),
      subject: Keyword.fetch!(opts, :subject),
      interval_ms: Keyword.get(opts, :interval_ms),
      duration_ms: Keyword.get(opts, :duration_ms),
      fields: Keyword.get(opts, :fields, @default_fields)
    ]

    with {:ok, frame} <- Frame.monitor_enable(frame_opts),
         :ok <- push(state, frame) do
      pending = %{
        request_id: request_id,
        owner: owner,
        agent_address: frame_opts[:agent_address],
        subject: frame_opts[:subject],
        fields: frame_opts[:fields]
      }

      state =
        state
        |> Map.update!(:pending, &Map.put(&1, request_id, pending))
        |> watch_owner(owner)
        |> log(:sent, "monitor.enable #{short_address(frame_opts[:agent_address])}")

      {:reply, {:ok, request_id}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp apply_monitor("enabled", frame, state) do
    request_id = Map.get(frame, "request_id")
    subscription_id = Map.get(frame, "subscription_id")

    case Map.pop(state.pending, request_id) do
      {nil, _pending} ->
        log(state, :note, "monitor.enabled for an unknown request")

      {pending, remaining} ->
        subscription = %{
          id: subscription_id,
          request_id: request_id,
          owner: pending.owner,
          agent_address: pending.agent_address,
          subject: pending.subject,
          fields: pending.fields,
          interval_ms: Map.get(frame, "interval_ms"),
          duration_ms: Map.get(frame, "duration_ms"),
          sequence: 0,
          dropped: 0,
          gaps: 0,
          series: %{},
          latest: %{},
          status: :streaming
        }

        subscription = absorb_snapshot(subscription, Map.get(frame, "snapshot", %{}), 0, 0)

        state = %{
          state
          | pending: remaining,
            subscriptions: Map.put(state.subscriptions, subscription_id, subscription)
        }

        broadcast(state, {:monitor_enabled, state.spec.id, request_id, subscription_id})
        broadcast_update(state, subscription)
        log(state, :received, "monitor.enabled #{short(subscription_id)}")
    end
  end

  defp apply_monitor("update", frame, state) do
    subscription_id = Map.get(frame, "subscription_id")

    case Map.fetch(state.subscriptions, subscription_id) do
      {:ok, subscription} ->
        sequence = Map.get(frame, "sequence", subscription.sequence + 1)
        dropped = Map.get(frame, "dropped_updates", 0)

        subscription =
          absorb_snapshot(subscription, Map.get(frame, "snapshot", %{}), sequence, dropped)

        state = put_subscription(state, subscription)
        broadcast_update(state, subscription)
        state

      :error ->
        state
    end
  end

  defp apply_monitor("disabled", frame, state) do
    subscription_id = Map.get(frame, "subscription_id")

    state
    |> log(:received, "monitor.disabled #{short(subscription_id)}")
    |> drop_subscription(subscription_id)
  end

  defp apply_monitor("expired", frame, state) do
    subscription_id = Map.get(frame, "subscription_id")

    state
    |> mark_subscription(subscription_id, :expired)
    |> log(:note, "monitor.expired #{short(subscription_id)}")
  end

  defp apply_monitor("error", frame, state) do
    subscription_id = Map.get(frame, "subscription_id")
    error = Map.get(frame, "error", %{})
    label = "#{Map.get(error, "kind", "unknown")}/#{Map.get(error, "code", "unknown")}"

    state
    |> mark_subscription(subscription_id, {:error, label})
    |> log(:fail, "monitor.error #{label}")
  end

  defp apply_monitor(event, _frame, state) do
    log(state, :note, "monitor.#{event} ignored")
  end

  # Folds one snapshot into the subscription's buffers.
  #
  # A sequence jump or a non-zero `dropped_updates` means samples were never
  # observed. They enter the series as explicit holes: an interpolated line would
  # read as measurement, and it is not.
  defp absorb_snapshot(subscription, snapshot, sequence, dropped) do
    process = Map.get(snapshot, "process", %{})
    missed = max(sequence - subscription.sequence - 1, 0) + max(dropped - subscription.dropped, 0)

    series =
      Enum.reduce(subscription.fields, subscription.series, fn field, series ->
        value = Map.get(process, field)
        samples = Map.get(series, field, [])

        samples =
          if is_number(value) do
            samples ++ List.duplicate(nil, min(missed, 5)) ++ [value]
          else
            samples
          end

        Map.put(series, field, Enum.take(samples, -@series_length))
      end)

    %{
      subscription
      | sequence: sequence,
        dropped: dropped,
        gaps: subscription.gaps + if(missed > 0, do: 1, else: 0),
        series: series,
        latest: process,
        status: :streaming
    }
  end

  defp broadcast_update(state, subscription) do
    broadcast(
      state,
      {:monitor_update, state.spec.id, subscription.id, public_subscription(subscription)}
    )
  end

  defp notify_subscriptions_lost(state) do
    Enum.each(state.subscriptions, fn {id, _subscription} ->
      broadcast(state, {:monitor_lost, state.spec.id, id})
    end)

    state
  end

  defp disable_owned_by(pid, state) do
    state.subscriptions
    |> Enum.filter(fn {_id, subscription} -> subscription.owner == pid end)
    |> Enum.reduce(state, fn {id, _subscription}, state ->
      case Frame.monitor_disable(id) do
        {:ok, frame} -> push(state, frame)
        _error -> :ok
      end

      state
      |> log(:note, "panel closed, monitor.disable #{short(id)}")
      |> drop_subscription(id)
    end)
    |> Map.update!(:owners, &Map.delete(&1, pid))
  end

  defp watch_owner(state, owner) do
    if Map.has_key?(state.owners, owner) do
      state
    else
      ref = Process.monitor(owner)
      Map.update!(state, :owners, &Map.put(&1, owner, ref))
    end
  end

  defp put_subscription(state, subscription) do
    %{state | subscriptions: Map.put(state.subscriptions, subscription.id, subscription)}
  end

  defp drop_subscription(state, nil), do: state

  defp drop_subscription(state, subscription_id) do
    broadcast(state, {:monitor_ended, state.spec.id, subscription_id})
    %{state | subscriptions: Map.delete(state.subscriptions, subscription_id)}
  end

  defp mark_subscription(state, nil, _status), do: state

  defp mark_subscription(state, subscription_id, status) do
    case Map.fetch(state.subscriptions, subscription_id) do
      {:ok, subscription} ->
        subscription = %{subscription | status: status}
        state = put_subscription(state, subscription)
        broadcast_update(state, subscription)
        state

      :error ->
        state
    end
  end

  # --- envelopes -------------------------------------------------------------

  defp studio_identity(%{manifest: %Manifest{principal_identity: identity}})
       when is_binary(identity),
       do: {:ok, identity}

  defp studio_identity(_state), do: {:error, :unknown_studio_identity}

  defp track_sent(state, envelope) do
    entry = %{
      id: envelope["id"],
      to: envelope["to"],
      act: envelope["act"],
      type: envelope["payload"]["type"],
      at: DateTime.utc_now(),
      receipt: nil
    }

    broadcast(state, {:envelope_sent, state.spec.id, entry})
    %{state | sent: Map.put(state.sent, entry.id, entry)}
  end

  defp put_receipt(state, nil, _receipt), do: state

  defp put_receipt(state, id, receipt) do
    case Map.fetch(state.sent, id) do
      {:ok, entry} ->
        entry = %{entry | receipt: receipt}
        broadcast(state, {:envelope_receipt, state.spec.id, entry})
        %{state | sent: Map.put(state.sent, id, entry)}

      :error ->
        state
    end
  end

  # --- projections -----------------------------------------------------------

  defp public(state) do
    %{
      id: state.spec.id,
      spec: ConnectionSpec.to_public(state.spec),
      display_url: ConnectionSpec.display_url(state.spec),
      status: state.status,
      manifest: state.manifest,
      last_error: state.last_error,
      attempt: state.attempt,
      events: state.events,
      subscriptions:
        Map.new(state.subscriptions, fn {id, subscription} ->
          {id, public_subscription(subscription)}
        end),
      sent: state.sent |> Map.values() |> Enum.sort_by(& &1.at, {:desc, DateTime})
    }
  end

  defp public_subscription(subscription) do
    Map.take(subscription, [
      :id,
      :request_id,
      :agent_address,
      :subject,
      :fields,
      :interval_ms,
      :duration_ms,
      :sequence,
      :dropped,
      :gaps,
      :series,
      :latest,
      :status
    ])
  end

  # --- plumbing --------------------------------------------------------------

  defp push(%{socket: nil}, _frame), do: {:error, :not_connected}
  defp push(%{socket: socket}, frame), do: Socket.send_text(socket, frame)

  defp transition(state, status) do
    state = %{state | status: status}
    broadcast(state, {:connection_status, state.spec.id, status})
    Events.directory_changed()
    state
  end

  # Every event carries a stable id so the UI can stream it into the DOM instead
  # of re-rendering the whole log on each line.
  defp log(state, kind, text) do
    seq = state.event_seq + 1
    event = %{id: "event-#{seq}", seq: seq, at: DateTime.utc_now(), kind: kind, text: text}
    broadcast(state, {:connection_event, state.spec.id, event})

    %{state | events: Enum.take([event | state.events], @event_log_length), event_seq: seq}
  end

  defp broadcast(state, message) do
    Events.broadcast(Events.connection_topic(state.spec.id), message)
  end

  defp normalize_reason({:shutdown, reason}), do: reason
  defp normalize_reason(reason), do: reason

  defp describe({:transport, reason}), do: "transport #{inspect(reason)}"
  defp describe({:http, reason}), do: "http #{inspect(reason)}"
  defp describe({:closed, code, _reason}), do: "closed by peer (#{code})"
  defp describe({:upgrade_failed, status}), do: "upgrade rejected (#{status})"
  defp describe(:unauthorized), do: "authentication rejected"
  defp describe(:invalid_url), do: "invalid endpoint URL"
  defp describe(:handshake_timeout), do: "handshake timed out"
  defp describe(:normal), do: "closed"
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(reason), do: inspect(reason)

  defp short(nil), do: "—"
  defp short(id) when is_binary(id), do: String.slice(id, 0, 8) <> "…"

  defp short_address(address), do: address |> String.split("/") |> List.last()
end
