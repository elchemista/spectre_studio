defmodule SpectreStudio.Pulse.ScopesTest do
  use ExUnit.Case, async: true

  alias SpectreStudio.Pulse.Manifest
  alias SpectreStudio.Pulse.Scopes

  defp manifest(scopes) do
    %Manifest{connection_id: "c", granted_scopes: scopes}
  end

  test "grants only what the manifest states" do
    manifest = manifest(["agent.runtime.read"])

    assert Scopes.can?(manifest, :runtime_read)
    refute Scopes.can?(manifest, :monitor_stream)
    refute Scopes.can?(manifest, :message_send)
  end

  test "a connection with no manifest grants nothing" do
    for capability <- Scopes.capabilities() do
      refute Scopes.can?(nil, capability)
    end
  end

  test "partitions into granted and withheld so the UI can explain itself" do
    partition = Scopes.partition(manifest(["agent.runtime.read", "custom.scope"]))

    assert "agent.runtime.read" in partition.granted
    assert "custom.scope" in partition.granted
    assert "agent.runtime.stream" in partition.withheld
    refute "agent.runtime.read" in partition.withheld
  end
end
