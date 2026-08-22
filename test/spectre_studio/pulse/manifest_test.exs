defmodule SpectreStudio.Pulse.ManifestTest do
  use ExUnit.Case, async: true

  alias SpectreStudio.Pulse.Manifest

  @frame %{
    "connection" => %{
      "id" => "conn-1",
      "spec_id" => "studio",
      "transport" => "websocket",
      "status" => "open",
      "principal" => %{"id" => "op-1", "identity" => "spectre://studio/op-1", "kind" => "studio"},
      "granted_scopes" => ["agent.runtime.read"],
      "granted_profiles" => ["spectre.studio/1"]
    },
    "spec" => %{"mode" => "listen", "scopes" => ["agent.runtime.read"], "profiles" => []},
    "agents" => [
      %{
        "address" => "spectre://acme/researcher",
        "display_name" => "Researcher",
        "capabilities" => ["research"],
        "protocol_versions" => [1]
      }
    ]
  }

  test "normalises a well formed manifest" do
    assert {:ok, manifest} = Manifest.normalize(@frame)
    assert manifest.connection_id == "conn-1"
    assert manifest.principal_identity == "spectre://studio/op-1"
    assert manifest.granted_scopes == ["agent.runtime.read"]
    assert [agent] = manifest.agents
    assert agent.address == "spectre://acme/researcher"
  end

  test "survives missing sections without inventing capability" do
    assert {:ok, manifest} = Manifest.normalize(%{"connection" => %{"id" => "conn-2"}})
    assert manifest.agents == []
    assert manifest.granted_scopes == []
    assert manifest.principal_identity == nil
  end

  test "discards descriptors it cannot address" do
    frame = put_in(@frame["agents"], [%{"display_name" => "no address"}, %{"address" => 42}])
    assert {:ok, manifest} = Manifest.normalize(frame)
    assert manifest.agents == []
  end

  test "keeps only string scopes, whatever the peer sends" do
    frame = put_in(@frame["connection"]["granted_scopes"], ["ok", 1, %{"a" => 1}])
    assert {:ok, manifest} = Manifest.normalize(frame)
    assert manifest.granted_scopes == ["ok"]
  end

  test "rejects a frame that is not a manifest" do
    assert {:error, :invalid_manifest} = Manifest.normalize(%{"nope" => true})
  end

  test "finds an exposed agent by address" do
    {:ok, manifest} = Manifest.normalize(@frame)
    assert {:ok, agent} = Manifest.fetch_agent(manifest, "spectre://acme/researcher")
    assert agent.display_name == "Researcher"
    assert :error = Manifest.fetch_agent(manifest, "spectre://acme/other")
  end
end
