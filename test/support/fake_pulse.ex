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
        {:ok, %{"type" => "agent.runtime.monitor.enable"} = frame} -> enable(frame, state)
        {:ok, %{"type" => "agent.runtime.monitor.disable"} = frame} -> disable(frame, state)
        {:ok, %{"payload" => _payload} = envelope} -> receipt(envelope, state)
        _other -> {:ok, state}
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
              "type" => "agent.runtime.monitor.update",
              "subscription_id" => subscription_id,
              "sequence" => sequence + Keyword.get(state.opts, :sequence_skip, 0) * sequence,
              "dropped_updates" => dropped,
              "snapshot" => snapshot(sequence)
            })

          {:push, {:text, frame}, state}

        :error ->
          {:ok, state}
      end
    end

    def handle_info({:expire, subscription_id}, state) do
      frame =
        encode(%{
          "type" => "agent.runtime.monitor.expired",
          "subscription_id" => subscription_id
        })

      {:push, {:text, frame},
       %{state | subscriptions: Map.delete(state.subscriptions, subscription_id)}}
    end

    def handle_info({:fail, subscription_id}, state) do
      frame =
        encode(%{
          "type" => "agent.runtime.monitor.error",
          "subscription_id" => subscription_id,
          "sequence" => 4,
          "error" => %{"kind" => "routing", "code" => "instance_not_found"}
        })

      {:push, {:text, frame}, state}
    end

    def handle_info(_message, state), do: {:ok, state}

    @impl WebSock
    def terminate(_reason, _state), do: :ok

    defp enable(frame, state) do
      counter = state.counter + 1
      subscription_id = "sub-#{counter}"
      interval = Map.get(frame, "interval_ms", 1000)

      subscription = %{
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
          "type" => "agent.runtime.monitor.enabled",
          "request_id" => subscription.request_id,
          "subscription_id" => subscription_id,
          "agent_address" => Map.get(frame, "agent_address"),
          "subject_id" => Map.get(frame, "subject"),
          "interval_ms" => interval,
          "sequence" => 0,
          "dropped_updates" => 0,
          "snapshot" => snapshot(0)
        })

      {:push, {:text, response}, state}
    end

    defp disable(frame, state) do
      subscription_id = Map.get(frame, "subscription_id")

      response =
        encode(%{
          "type" => "agent.runtime.monitor.disabled",
          "subscription_id" => subscription_id
        })

      {:push, {:text, response},
       %{state | subscriptions: Map.delete(state.subscriptions, subscription_id)}}
    end

    defp receipt(envelope, state) do
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

    defp schedule(subscription_id, interval_ms) do
      Process.send_after(self(), {:sample, subscription_id}, interval_ms)
    end

    defp snapshot(sequence) do
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

    defp default_scopes, do: ["agent.runtime.read", "agent.runtime.stream"]

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
