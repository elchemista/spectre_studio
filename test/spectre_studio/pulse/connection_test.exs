defmodule SpectreStudio.Pulse.ConnectionTest do
  use ExUnit.Case, async: false

  alias SpectreStudio.FakePulse
  alias SpectreStudio.Pulse.Connection
  alias SpectreStudio.Pulse.ConnectionSpec
  alias SpectreStudio.Pulse.Events

  @address "spectre://acme/researcher"

  defp start_endpoint(opts \\ []) do
    {:ok, port, pid} = FakePulse.start(opts)
    on_exit(fn -> stop_endpoint(pid) end)
    port
  end

  # Bandit's supervisor exits with :shutdown rather than :normal, so it is taken
  # down by signal and waited for, instead of through Supervisor.stop/1.
  defp stop_endpoint(pid) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      Process.exit(pid, :shutdown)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        2_000 -> :ok
      end
    end
  end

  defp start_connection(port, token \\ "good-token") do
    {:ok, spec} =
      ConnectionSpec.new(%{
        "label" => "test-#{System.unique_integer([:positive])}",
        "url" => FakePulse.url(port),
        "token" => token
      })

    :ok = Events.subscribe(Events.connection_topic(spec.id))
    start_supervised!({Connection, spec: spec}, id: {:connection, spec.id})
    spec
  end

  describe "connecting" do
    test "reaches ready once the manifest arrives" do
      spec = start_connection(start_endpoint())
      Connection.connect(spec.id)

      assert_receive {:connection_status, _id, :connecting}, 2_000
      assert_receive {:connection_status, _id, :authenticating}, 2_000
      assert_receive {:connection_status, _id, :ready}, 2_000

      assert {:ok, snapshot} = Connection.snapshot(spec.id)
      assert snapshot.manifest.principal_id == "operator-42"
      assert [agent] = snapshot.manifest.agents
      assert agent.address == @address
    end

    test "a rejected credential is terminal, not retried forever" do
      spec = start_connection(start_endpoint(), "wrong-token")
      Connection.connect(spec.id)

      assert_receive {:connection_status, _id, :connecting}, 2_000
      assert_receive {:connection_status, _id, :error}, 5_000

      assert {:ok, snapshot} = Connection.snapshot(spec.id)
      assert snapshot.last_error == "authentication rejected"
      # No reconnection is scheduled for a credential the host has rejected.
      refute_receive {:connection_status, _id, :connecting}, 1_500
    end
  end

  describe "runtime monitoring" do
    setup do
      spec = start_connection(start_endpoint())
      Connection.connect(spec.id)
      assert_receive {:connection_status, _id, :ready}, 2_000
      {:ok, spec: spec}
    end

    test "enable, stream and disable", %{spec: spec} do
      assert {:ok, _request_id} =
               Connection.enable_monitor(spec.id,
                 agent_address: @address,
                 subject: "account-1",
                 interval_ms: 250
               )

      assert_receive {:monitor_enabled, _id, _request, subscription_id}, 2_000
      assert_receive {:monitor_update, _id, ^subscription_id, subscription}, 2_000

      assert subscription.agent_address == @address
      assert is_list(subscription.series["memory"])
      assert Enum.all?(subscription.series["memory"], &(is_number(&1) or is_nil(&1)))

      # Samples keep arriving until we say stop.
      assert_receive {:monitor_update, _id, ^subscription_id, later}, 2_000
      assert later.sequence > 0

      assert :ok = Connection.disable_monitor(spec.id, subscription_id)
      assert_receive {:monitor_ended, _id, ^subscription_id}, 2_000
    end

    test "refuses to enable before the connection is ready" do
      {:ok, other} =
        ConnectionSpec.new(%{"label" => "idle", "url" => "wss://nowhere/pulse"})

      start_supervised!({Connection, spec: other}, id: {:connection, other.id})

      assert {:error, :not_ready} =
               Connection.enable_monitor(other.id,
                 agent_address: @address,
                 subject: "account-1"
               )
    end

    test "invalid monitor input does not crash the connection", %{spec: spec} do
      assert {:error, {:missing_monitor_field, :subject}} =
               Connection.enable_monitor(spec.id, agent_address: @address)

      assert {:ok, %{status: :ready}} = Connection.snapshot(spec.id)
    end

    test "correlates an initial monitor rejection and releases the pending request" do
      rejected = start_connection(start_endpoint(reject_subject: "missing-instance"))
      Connection.connect(rejected.id)
      assert_receive {:connection_status, rejected_id, :ready}, 2_000
      assert rejected_id == rejected.id

      assert {:ok, request_id} =
               Connection.enable_monitor(rejected.id,
                 agent_address: @address,
                 subject: "missing-instance"
               )

      assert_receive {:monitor_failed, ^rejected_id, ^request_id, error}, 2_000
      assert error["kind"] == "routing"
      assert error["code"] == "instance_not_found"
      refute_receive {:monitor_enabled, ^rejected_id, ^request_id, _subscription_id}, 100

      assert {:ok, snapshot} = Connection.snapshot(rejected.id)
      assert snapshot.last_error == "routing/instance_not_found"
    end

    test "releases an unanswered monitor request when the connection closes" do
      unanswered = start_connection(start_endpoint(ignore_subject: "slow-instance"))
      Connection.connect(unanswered.id)
      assert_receive {:connection_status, unanswered_id, :ready}, 2_000
      assert unanswered_id == unanswered.id

      assert {:ok, request_id} =
               Connection.enable_monitor(unanswered.id,
                 agent_address: @address,
                 subject: "slow-instance"
               )

      Connection.disconnect(unanswered.id)

      assert_receive {:monitor_failed, ^unanswered_id, ^request_id, error}, 2_000
      assert error == %{"kind" => "transport", "code" => "connection_lost"}
      assert_receive {:connection_status, ^unanswered_id, :closed}, 2_000
    end

    test "a dead panel takes its subscription with it", %{spec: spec} do
      test_pid = self()

      owner =
        spawn(fn ->
          Connection.enable_monitor(spec.id,
            agent_address: @address,
            subject: "account-1",
            interval_ms: 250
          )

          send(test_pid, :enabled)
          Process.sleep(:infinity)
        end)

      assert_receive :enabled, 2_000
      assert_receive {:monitor_enabled, _id, _request, subscription_id}, 2_000

      Process.exit(owner, :kill)

      # Studio mirrors the guarantee Pulse gives on the host side: nobody is
      # left streaming to a reader that no longer exists.
      assert_receive {:monitor_ended, _id, ^subscription_id}, 2_000
      assert {:ok, snapshot} = Connection.snapshot(spec.id)
      assert snapshot.subscriptions == %{}
    end
  end

  describe "Work and Vigil monitoring" do
    setup do
      port =
        start_endpoint(
          scopes: [
            "agent.runtime.read",
            "agent.runtime.stream",
            "agent.operations.read",
            "agent.operations.stream"
          ]
        )

      spec = start_connection(port)
      Connection.connect(spec.id)
      assert_receive {:connection_status, _id, :ready}, 2_000
      {:ok, spec: spec}
    end

    test "streams complete bounded operation snapshots", %{spec: spec} do
      assert {:ok, _request_id} =
               Connection.enable_operations_monitor(spec.id,
                 agent_address: @address,
                 subject: "account-1",
                 interval_ms: 250,
                 kinds: ["work", "vigil"]
               )

      assert_receive {:operations_monitor_enabled, _id, _request, subscription_id}, 2_000

      assert_receive {:operations_monitor_update, _id, ^subscription_id, subscription},
                     2_000

      assert subscription.kind == :operations
      assert subscription.snapshot["counts"] == %{"total" => 2, "work" => 1, "vigil" => 1}
      assert Enum.count(subscription.snapshot["operations"]) == 2

      assert :ok = Connection.disable_monitor(spec.id, subscription_id)
      assert_receive {:operations_monitor_ended, _id, ^subscription_id}, 2_000
    end

    test "an explicit disconnect terminates every panel subscription", %{spec: spec} do
      assert {:ok, _request_id} =
               Connection.enable_operations_monitor(spec.id,
                 agent_address: @address,
                 subject: "account-1"
               )

      assert_receive {:operations_monitor_enabled, _id, _request, subscription_id}, 2_000
      Connection.disconnect(spec.id)
      assert_receive {:operations_monitor_lost, _id, ^subscription_id}, 2_000
    end
  end

  describe "envelopes" do
    setup do
      spec = start_connection(start_endpoint())
      Connection.connect(spec.id)
      assert_receive {:connection_status, _id, :ready}, 2_000
      {:ok, spec: spec}
    end

    test "sends a validated envelope and correlates its receipt", %{spec: spec} do
      assert {:ok, envelope} =
               Connection.send_envelope(spec.id,
                 to: @address,
                 act: "request",
                 payload_type: "research.perform",
                 data: %{"text" => "hello"}
               )

      assert envelope["from"] == "spectre://studio/operator-42"

      assert_receive {:envelope_sent, _id, _entry}, 2_000
      assert_receive {:envelope_receipt, _id, entry}, 2_000
      assert entry.id == envelope["id"]
      assert entry.receipt["status"] == "accepted"
    end

    test "a malformed envelope never reaches the network", %{spec: spec} do
      assert {:error, :invalid_payload_type} =
               Connection.send_envelope(spec.id, to: @address, act: "inform", payload_type: "")
    end
  end
end
