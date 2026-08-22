defmodule SpectreStudio.FakePulse do
  @moduledoc """
  A stand-in for the server half of the Pulse connection protocol.

  It speaks the frames documented in `spectre_pulse/docs/STUDIO_MONITORING.md` —
  manifest, receipts, errors and the full monitoring lifecycle including
  sequence numbers, coalesced updates, expiry and sampling errors. That makes
  the connection layer testable without an application running Spectre, and it
  is the only way to exercise the failure paths (a dropped socket mid-stream, an
  Instance that disappears) on demand.
  """

  @behaviour Plug

  @doc "Finds a free port and starts a fake endpoint on it."
  @spec start(keyword()) :: {:ok, pos_integer(), pid()}
  def start(opts \\ []) do
    port = free_port()

    {:ok, pid} =
      Bandit.start_link(
        plug: {__MODULE__, opts},
        scheme: :http,
        port: port,
        startup_log: false
      )

    {:ok, port, pid}
  end

  @doc "The URL of a fake endpoint on one port."
  @spec url(pos_integer()) :: String.t()
  def url(port), do: "ws://127.0.0.1:#{port}/pulse/websocket"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    conn = Plug.Conn.fetch_query_params(conn)
    expected = Keyword.get(opts, :token, "good-token")

    if Map.get(conn.query_params, "token") == expected do
      conn
      |> WebSockAdapter.upgrade(__MODULE__.Socket, opts, timeout: 60_000)
      |> Plug.Conn.halt()
    else
      conn
      |> Plug.Conn.send_resp(401, "unauthorized")
      |> Plug.Conn.halt()
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defmodule Socket do
    @moduledoc false

    @behaviour WebSock

    @impl WebSock
    def init(opts) do
      state = %{
        opts: opts,
        subscriptions: %{},
        counter: 0
      }

      if Keyword.get(opts, :manifest, true) do
        {:push, {:text, manifest_frame(opts)}, state}
      else
        {:ok, state}
      end
    end

    @impl WebSock
    def handle_in({text, opcode: :text}, state) do
      case Jason.decode(text) do
        {:ok, %{"type" => "agent.runtime.monitor.enable"} = frame} ->
          enable(:runtime, frame, state)

        {:ok, %{"type" => "agent.runtime.monitor.disable"} = frame} ->
          disable(:runtime, frame, state)

        {:ok, %{"type" => "agent.operations.monitor.enable"} = frame} ->
          enable(:operations, frame, state)

        {:ok, %{"type" => "agent.operations.monitor.disable"} = frame} ->
          disable(:operations, frame, state)

        {:ok, %{"payload" => _payload} = envelope} ->
          receipt(envelope, state)

        _other ->
          {:ok, state}
      end
    end

    def handle_in(_message, state), do: {:ok, state}

    @impl WebSock
    def handle_info({:sample, subscription_id}, state) do
      case Map.fetch(state.subscriptions, subscription_id) do
        {:ok, subscription} ->
          sequence = subscription.sequence + 1
          dropped = Keyword.get(state.opts, :dropped_updates, 0)
          schedule(subscription_id, subscription.interval_ms)

          state = put_in(state.subscriptions[subscription_id].sequence, sequence)

          frame =
            encode(%{
              "type" => monitor_type(subscription.kind, "update"),
              "subscription_id" => subscription_id,
              "sequence" => sequence + Keyword.get(state.opts, :sequence_skip, 0) * sequence,
              "dropped_updates" => dropped,
              "snapshot" => snapshot(subscription.kind, sequence)
            })

          {:push, {:text, frame}, state}

        :error ->
          {:ok, state}
      end
    end

    def handle_info({:expire, subscription_id}, state) do
      case Map.pop(state.subscriptions, subscription_id) do
        {nil, _subscriptions} ->
          {:ok, state}

        {subscription, subscriptions} ->
          frame =
            encode(%{
              "type" => monitor_type(subscription.kind, "expired"),
              "subscription_id" => subscription_id
            })

          {:push, {:text, frame}, %{state | subscriptions: subscriptions}}
      end
    end

    def handle_info({:fail, subscription_id}, state) do
      case Map.fetch(state.subscriptions, subscription_id) do
        {:ok, subscription} ->
          frame =
            encode(%{
              "type" => monitor_type(subscription.kind, "error"),
              "subscription_id" => subscription_id,
              "sequence" => 4,
              "error" => %{"kind" => "routing", "code" => "instance_not_found"}
            })

          {:push, {:text, frame}, state}

        :error ->
          {:ok, state}
      end
    end

    def handle_info({:bridge_reply, envelope}, state) do
      {:push, {:text, bridge_response(envelope)}, state}
    end

    def handle_info(_message, state), do: {:ok, state}

    @impl WebSock
    def terminate(_reason, _state), do: :ok

    defp enable(kind, frame, state) do
      subject = Map.get(frame, "subject")

      cond do
        subject == Keyword.get(state.opts, :reject_subject) -> reject_enable(kind, frame, state)
        subject == Keyword.get(state.opts, :ignore_subject) -> {:ok, state}
        true -> accept_enable(kind, frame, state)
      end
    end

    defp reject_enable(kind, frame, state) do
      response =
        encode(%{
          "type" => "error",
          "error" => %{
            "kind" => "routing",
            "outcome" => "not_sent",
            "code" => "instance_not_found",
            "message_id" => nil,
            "monitor" => Atom.to_string(kind),
            "request_id" => Map.get(frame, "request_id")
          }
        })

      {:push, {:text, response}, state}
    end

    defp accept_enable(kind, frame, state) do
      counter = state.counter + 1
      subscription_id = "sub-#{counter}"
      interval = Map.get(frame, "interval_ms", 1000)

      subscription = %{
        kind: kind,
        id: subscription_id,
        request_id: Map.get(frame, "request_id"),
        interval_ms: interval,
        sequence: 0
      }

      schedule(subscription_id, interval)

      if duration = Map.get(frame, "duration_ms") do
        Process.send_after(self(), {:expire, subscription_id}, duration)
      end

      state = %{
        state
        | counter: counter,
          subscriptions: Map.put(state.subscriptions, subscription_id, subscription)
      }

      response =
        encode(%{
          "type" => monitor_type(kind, "enabled"),
          "monitor" => Atom.to_string(kind),
          "request_id" => subscription.request_id,
          "subscription_id" => subscription_id,
          "agent_address" => Map.get(frame, "agent_address"),
          "subject_id" => Map.get(frame, "subject"),
          "interval_ms" => interval,
          "sequence" => 0,
          "dropped_updates" => 0,
          "snapshot" => snapshot(kind, 0)
        })

      {:push, {:text, response}, state}
    end

    defp disable(kind, frame, state) do
      subscription_id = Map.get(frame, "subscription_id")

      response =
        encode(%{
          "type" => monitor_type(kind, "disabled"),
          "subscription_id" => subscription_id
        })

      {:push, {:text, response},
       %{state | subscriptions: Map.delete(state.subscriptions, subscription_id)}}
    end

    defp receipt(envelope, state) do
      if String.starts_with?(get_in(envelope, ["payload", "type"]) || "", "studio.") do
        send(self(), {:bridge_reply, envelope})
      end

      response =
        encode(%{
          "type" => "receipt",
          "receipt" => %{
            "message_id" => Map.get(envelope, "id"),
            "status" => "accepted",
            "via" => "websocket",
            "accepted_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        })

      {:push, {:text, response}, state}
    end

    defp bridge_response(envelope) do
      type = get_in(envelope, ["payload", "type"])

      response = %{
        "version" => 1,
        "id" => "reply-#{Map.get(envelope, "id")}",
        "from" => Map.get(envelope, "to"),
        "to" => Map.get(envelope, "from"),
        "act" => "inform",
        "relates_to" => Map.get(envelope, "id"),
        "payload" => %{"type" => type <> ".result", "data" => bridge_data(type, envelope)},
        "metadata" => %{}
      }

      Jason.encode!(response)
    end

    defp bridge_data("studio.semantic_cache.examples", _envelope) do
      %{
        "examples" => [
          %{
            "id" => "cache-1",
            "text" => "need a custom quote",
            "label" => "SALES",
            "verified?" => false
          },
          %{
            "id" => "cache-2",
            "text" => "pricing please",
            "label" => "PRICING",
            "verified?" => true
          }
        ]
      }
    end

    defp bridge_data("studio.semantic_cache.verify", envelope) do
      example_id = get_in(envelope, ["payload", "data", "example_id"])

      %{
        "example" => %{
          "id" => example_id,
          "text" => "need a custom quote",
          "label" => "SALES",
          "verified?" => true
        }
      }
    end

    defp bridge_data("studio.journal.turns", envelope) do
      subject = get_in(envelope, ["payload", "data", "subject"])

      %{
        "subject" => subject,
        "revision" => 7,
        "count" => 2,
        "turns" => [
          %{
            "at" => "2026-08-22T12:00:00Z",
            "user" => "show the latest article",
            "assistant" => "The latest article is Runtime Safety.",
            "route" => "read_latest",
            "events" => ["routed", "completed"]
          },
          %{
            "at" => "2026-08-22T12:01:00Z",
            "user" => "summarize it",
            "assistant" => "It explains bounded Agent operations.",
            "route" => "summarize",
            "events" => ["completed"]
          }
        ]
      }
    end

    defp bridge_data("studio.skills.list", _envelope) do
      %{
        "count" => 2,
        "skills" => [
          %{
            "id" => "reader",
            "module" => "SpectreStudio.Fake.Reader",
            "definition_id" => "reader",
            "definition_version" => 3,
            "origin" => "compiled"
          },
          %{
            "id" => "refunds",
            "module" => "runtime",
            "definition_id" => "refunds",
            "definition_version" => 1,
            "origin" => "runtime"
          }
        ]
      }
    end

    defp bridge_data("studio.morph.propose_skill", _envelope) do
      %{
        "state" => "evaluated",
        "candidate_ref" => "candidate:sha256:test",
        "operation_count" => 3,
        "approved" => false,
        "activated" => false
      }
    end

    defp bridge_data(_type, _envelope), do: %{"status" => "accepted"}

    defp schedule(subscription_id, interval_ms) do
      Process.send_after(self(), {:sample, subscription_id}, interval_ms)
    end

    defp snapshot(:runtime, sequence) do
      %{
        "sampled_at_unix_ms" => System.system_time(:millisecond),
        "process" => %{
          "memory" => 42_000 + sequence * 128,
          "message_queue_len" => rem(sequence, 3),
          "reductions" => 18_000 + sequence * 500,
          "status" => "waiting",
          "total_heap_size" => 2_500 + sequence
        }
      }
    end

    defp snapshot(:operations, sequence) do
      work_status = if rem(sequence, 2) == 0, do: "waiting", else: "running"

      %{
        "schema_version" => 1,
        "capability" => "agent.operations.list",
        "sampled_at_unix_ms" => System.system_time(:millisecond),
        "counts" => %{"total" => 2, "work" => 1, "vigil" => 1},
        "truncated" => false,
        "operations" => [
          %{
            "id" => "work-1",
            "kind" => "work",
            "definition" => "research_pages",
            "status" => work_status,
            "phase" => "reading",
            "operation" => "fetch_page",
            "progress" => %{"completed" => sequence, "total" => 12},
            "retries" => 0,
            "budget" => %{"remaining" => %{"steps" => 500 - sequence}}
          },
          %{
            "id" => "vigil-1",
            "kind" => "vigil",
            "definition" => "cache_watch",
            "status" => "waiting",
            "phase" => "observe",
            "operation" => "watch",
            "retries" => 0
          }
        ]
      }
    end

    defp monitor_type(kind, action), do: "agent.#{kind}.monitor.#{action}"

    defp manifest_frame(opts) do
      encode(%{
        "type" => "manifest",
        "connection" => %{
          "id" => "conn-1",
          "spec_id" => "studio",
          "peer_id" => "studio.test",
          "transport" => "websocket",
          "status" => "open",
          "connected_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "principal" => %{
            "id" => "operator-42",
            "identity" => "spectre://studio/operator-42",
            "kind" => "studio",
            "scopes" => Keyword.get(opts, :scopes, default_scopes())
          },
          "granted_scopes" => Keyword.get(opts, :scopes, default_scopes()),
          "granted_profiles" => ["pulse.messaging/1", "spectre.studio/1"]
        },
        "spec" => %{
          "id" => "studio",
          "transport" => "websocket",
          "mode" => "listen",
          "profiles" => ["pulse.messaging/1", "spectre.studio/1"],
          "scopes" => default_scopes()
        },
        "agents" => Keyword.get(opts, :agents, default_agents())
      })
    end

    defp default_scopes,
      do: ["agent.runtime.read", "agent.runtime.stream", "agent.message.send"]

    defp default_agents do
      [
        %{
          "address" => "spectre://acme/researcher",
          "display_name" => "Researcher",
          "protocol_versions" => [1],
          "capabilities" => ["research"],
          "metadata" => %{}
        }
      ]
    end

    defp encode(frame) do
      frame
      |> Map.merge(%{"pulse" => "connection", "version" => 1})
      |> Jason.encode!()
    end
  end
end
