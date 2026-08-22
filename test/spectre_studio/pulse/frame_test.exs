defmodule SpectreStudio.Pulse.FrameTest do
  use ExUnit.Case, async: true

  alias SpectreStudio.Pulse.Frame

  describe "decode/1" do
    test "classifies each control frame" do
      assert {:ok, {:manifest, _frame}} =
               Frame.decode(~s({"pulse":"connection","version":1,"type":"manifest"}))

      assert {:ok, {:receipt, %{"message_id" => "abc"}}} =
               Frame.decode(
                 ~s({"pulse":"connection","version":1,"type":"receipt","receipt":{"message_id":"abc"}})
               )

      assert {:ok, {:error, %{"code" => "boom"}}} =
               Frame.decode(
                 ~s({"pulse":"connection","version":1,"type":"error","error":{"code":"boom"}})
               )

      assert {:ok, {:monitor, :runtime, "update", _frame}} =
               Frame.decode(
                 ~s({"pulse":"connection","version":1,"type":"agent.runtime.monitor.update"})
               )

      assert {:ok, {:monitor, :operations, "enabled", _frame}} =
               Frame.decode(
                 ~s({"pulse":"connection","version":1,"type":"agent.operations.monitor.enabled"})
               )
    end

    test "classifies an ordinary envelope" do
      frame = ~s({"version":1,"id":"1","from":"a","to":"b","payload":{"type":"x","data":{}}})
      assert {:ok, {:envelope, %{"id" => "1"}}} = Frame.decode(frame)
    end

    test "refuses a protocol version it does not speak" do
      assert {:error, :unsupported_version} =
               Frame.decode(~s({"pulse":"connection","version":99,"type":"manifest"}))
    end

    test "survives anything a peer can send" do
      assert {:error, :malformed} = Frame.decode("not json")
      assert {:error, :malformed} = Frame.decode("[1,2,3]")
      assert {:ok, {:unknown, _value}} = Frame.decode(~s({"hello":"world"}))
    end
  end

  describe "monitor frames" do
    test "enable carries only the fields that were given" do
      {:ok, frame} =
        Frame.monitor_enable(
          request_id: "req-1",
          agent_address: "spectre://acme/researcher",
          subject: "account-1",
          interval_ms: 1000
        )

      decoded = Jason.decode!(frame)

      assert decoded["type"] == "agent.runtime.monitor.enable"
      assert decoded["interval_ms"] == 1000
      refute Map.has_key?(decoded, "duration_ms")
    end

    test "disable names a server-issued subscription" do
      {:ok, frame} = Frame.monitor_disable("sub-1")
      assert Jason.decode!(frame)["subscription_id"] == "sub-1"
    end

    test "Work and Vigil enable uses the operations frame and filters" do
      {:ok, frame} =
        Frame.monitor_enable(:operations,
          request_id: "req-2",
          agent_address: "spectre://acme/researcher",
          subject: "account-1",
          kinds: ["work", "vigil"],
          include_terminal: true
        )

      decoded = Jason.decode!(frame)
      assert decoded["type"] == "agent.operations.monitor.enable"
      assert decoded["kinds"] == ["work", "vigil"]
      assert decoded["include_terminal"] == true

      {:ok, disable} = Frame.monitor_disable(:operations, "ops-1")
      assert Jason.decode!(disable)["type"] == "agent.operations.monitor.disable"
    end

    test "missing required fields are errors, not exceptions" do
      assert {:error, {:missing_monitor_field, :subject}} =
               Frame.monitor_enable(:runtime,
                 request_id: "req-1",
                 agent_address: "spectre://acme/researcher"
               )
    end
  end

  describe "envelope/1" do
    @valid [
      to: "spectre://acme/researcher",
      from: "spectre://studio/operator",
      act: "request",
      payload_type: "research.perform",
      data: %{"text" => "hello"}
    ]

    test "builds a validated envelope" do
      assert {:ok, frame, envelope} = Frame.envelope(@valid)
      assert envelope["act"] == "request"
      assert envelope["payload"]["type"] == "research.perform"
      assert Jason.decode!(frame)["id"] == envelope["id"]
    end

    test "rejects malformed input before the network" do
      assert {:error, :invalid_act} = Frame.envelope(Keyword.put(@valid, :act, "shout"))
      assert {:error, :invalid_address} = Frame.envelope(Keyword.put(@valid, :to, "http://x"))

      assert {:error, :invalid_payload_type} =
               Frame.envelope(Keyword.put(@valid, :payload_type, ""))

      assert {:error, :invalid_payload_data} = Frame.envelope(Keyword.put(@valid, :data, "text"))
    end
  end

  describe "uuid7/0" do
    test "is a version 7 UUID and increases with time" do
      first = Frame.uuid7()
      Process.sleep(2)
      second = Frame.uuid7()

      assert first =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
      assert first < second
    end
  end
end
