defmodule SpectreStudioWeb.AgentLive.PanelsTest do
  use SpectreStudioWeb.ConnCase, async: false

  alias SpectreStudio.FakePulse
  alias SpectreStudio.Pulse
  alias SpectreStudio.Pulse.Agent
  alias SpectreStudio.Pulse.Events
  alias SpectreStudio.Vault

  @address "spectre://acme/researcher"

  defp connected_endpoint(opts) do
    {:ok, port, server} = FakePulse.start(opts)
    on_exit(fn -> stop_endpoint(server) end)

    {:ok, spec} =
      Pulse.save(%{
        "label" => "test-#{System.unique_integer([:positive])}",
        "url" => FakePulse.url(port),
        "token" => "good-token"
      })

    :ok = Events.subscribe(Events.connection_topic(spec.id))
    :ok = Pulse.connect(spec.id)
    assert_receive {:connection_status, _id, :ready}, 5_000

    spec
  end

  defp stop_endpoint(server) do
    if Process.alive?(server) do
      ref = Process.monitor(server)
      Process.exit(server, :shutdown)

      receive do
        {:DOWN, ^ref, :process, ^server, _reason} -> :ok
      after
        2_000 -> :ok
      end
    end
  end

  setup do
    on_exit(fn -> Enum.each(Vault.list(), &Pulse.delete(&1.id)) end)
    :ok
  end

  describe "with both runtime scopes" do
    setup do
      {:ok, spec: connected_endpoint([])}
    end

    test "the connection page lists the exposed agents", %{conn: conn, spec: spec} do
      {:ok, _live, html} = live(conn, ~p"/connections/#{spec.id}")

      assert html =~ @address
      assert html =~ "Researcher"
      assert html =~ "agent.runtime.read"
      # Withheld scopes are shown too, so a missing panel has a visible reason.
      assert html =~ "lab.read"
    end

    test "the connection page streams its event log", %{conn: conn, spec: spec} do
      {:ok, live, html} = live(conn, ~p"/connections/#{spec.id}")

      assert html =~ ~s(id="connection-events-rows")
      assert html =~ ~s(phx-update="stream")
      assert html =~ "manifest:"

      Pulse.disconnect(spec.id)

      assert_eventually(live, "disconnect requested")
    end

    test "overview opens first and says what it cannot show", %{conn: conn, spec: spec} do
      {:ok, _live, html} = live(conn, agent_path(spec))

      assert html =~ "Researcher"
      assert html =~ "no mailbox contents"
      assert html =~ "belong to Ledger"
      assert html =~ "capability matrix"
      assert html =~ "Semantic cache · inspect"
      assert html =~ "locked"
    end

    test "an empty runtime has no subject control and explains how to start a process", %{
      conn: conn,
      spec: spec
    } do
      {:ok, live, html} = live(conn, agent_path(spec, :monitor))

      assert html =~ "not streaming"
      assert html =~ "No active Agent processes"
      assert has_element?(live, "#refresh-processes")
      refute has_element?(live, "#monitor_subject")
    end

    test "discovers a live Instance and starts OTP monitoring automatically", %{conn: conn} do
      spec = connected_endpoint(instances: ["conversation-42"])
      {:ok, live, _html} = live(conn, agent_path(spec, :monitor))

      assert_receive {:monitor_enabled, _id, _request, subscription_id}, 5_000
      assert_receive {:monitor_update, _id, ^subscription_id, _subscription}, 5_000

      html = render(live)
      assert html =~ "active processes"
      assert html =~ "process 1"
      refute has_element?(live, "#monitor_subject")
      assert html =~ "OTP process snapshot"
      assert html =~ "message_queue_len"
    end

    test "process discovery can be refreshed without operator identifiers", %{
      conn: conn,
      spec: spec
    } do
      {:ok, live, _html} = live(conn, agent_path(spec, :monitor))
      html = live |> element("#refresh-processes") |> render_click()
      assert html =~ "No active Agent processes"
      refute has_element?(live, "#monitor_subject")
    end

    test "leaving the monitor panel stops the stream", %{conn: conn} do
      spec = connected_endpoint(instances: ["account-1"])
      {:ok, live, _html} = live(conn, agent_path(spec, :monitor))

      assert_receive {:monitor_enabled, _id, _request, subscription_id}, 5_000

      # Each tab is its own LiveView, so navigating away ends the process that
      # owns the subscription.
      {:ok, _overview, html} =
        live |> element("a", "overview") |> render_click() |> follow_redirect(conn)

      assert html =~ "no mailbox contents"

      assert_receive {:monitor_ended, _id, ^subscription_id}, 5_000
      assert {:ok, snapshot} = Pulse.snapshot(spec.id)
      assert snapshot.subscriptions == %{}
    end

    test "the messages panel sends an envelope and streams its receipt", %{
      conn: conn,
      spec: spec
    } do
      {:ok, live, html} = live(conn, agent_path(spec, :messages))

      assert html =~ "nothing sent on this connection yet"

      live
      |> form("#message-form", %{
        "message" => %{
          "act" => "request",
          "payload_type" => "research.perform",
          "data" => ~s({"text":"hello"})
        }
      })
      |> render_submit()

      assert_receive {:envelope_receipt, _id, _entry}, 5_000

      html = render(live)
      assert html =~ "request · research.perform"
      assert html =~ "accepted"
    end

    test "a malformed payload never reaches the network", %{conn: conn, spec: spec} do
      {:ok, live, _html} = live(conn, agent_path(spec, :messages))

      html =
        live
        |> form("#message-form", %{
          "message" => %{"act" => "inform", "payload_type" => "x.y", "data" => "{oops"}
        })
        |> render_submit()

      assert html =~ "payload is not valid JSON"
    end

    test "the events panel streams the connection log", %{conn: conn, spec: spec} do
      {:ok, _live, html} = live(conn, agent_path(spec, :events))

      assert html =~ ~s(id="agent-events-rows")
      assert html =~ "manifest:"
    end
  end

  describe "without the streaming scope" do
    setup do
      {:ok, spec: connected_endpoint(scopes: ["agent.runtime.read"])}
    end

    test "the live tab remains visible but explains that it is locked", %{conn: conn, spec: spec} do
      {:ok, _live, html} = live(conn, agent_path(spec))

      assert html =~ "overview"
      assert html =~ ~s(aria-disabled="true")
      assert html =~ "not granted: agent.runtime.read, agent.runtime.stream"
      # The overview explains the absence instead of leaving it a mystery.
      assert html =~ "panels withheld by this connection"
      assert html =~ "agent.runtime.stream"
    end

    test "the hidden live panel cannot be opened by URL", %{conn: conn, spec: spec} do
      assert {:error, {:live_redirect, %{to: path}}} = live(conn, agent_path(spec, :monitor))
      assert path == "/connections/#{spec.id}"
    end
  end

  describe "with Work/Vigil scopes" do
    setup do
      scopes = [
        "agent.runtime.read",
        "agent.runtime.stream",
        "agent.operations.read",
        "agent.operations.stream"
      ]

      {:ok, spec: connected_endpoint(scopes: scopes, instances: ["account-1"])}
    end

    test "streams publication-safe Work and Vigil snapshots", %{conn: conn, spec: spec} do
      {:ok, live, html} = live(conn, agent_path(spec, :operations))
      assert html =~ "not streaming"

      assert_receive {:operations_monitor_enabled, _id, _request, subscription_id}, 5_000
      assert_receive {:operations_monitor_update, _id, ^subscription_id, _subscription}, 5_000

      html = render(live)
      assert html =~ "research_pages"
      assert html =~ "cache_watch"
      assert html =~ "publication-safe bounded snapshot"
    end
  end

  describe "when Pulse rejects the requested Instance" do
    setup do
      scopes = [
        "agent.runtime.read",
        "agent.runtime.stream",
        "agent.operations.read",
        "agent.operations.stream"
      ]

      {:ok,
       spec:
         connected_endpoint(
           scopes: scopes,
           instances: ["missing-instance"],
           reject_subject: "missing-instance"
         )}
    end

    test "the runtime panel leaves enabling and displays the correlated error", %{
      conn: conn,
      spec: spec
    } do
      {:ok, live, _html} = live(conn, agent_path(spec, :monitor))

      assert_eventually(live, "routing/instance_not_found")
      html = render(live)
      refute html =~ "enabling…"
      assert html =~ "start live"
      refute has_element?(live, "#monitor_subject")
    end

    test "the Work/Vigil panel leaves enabling and displays the correlated error", %{
      conn: conn,
      spec: spec
    } do
      {:ok, live, _html} = live(conn, agent_path(spec, :operations))

      assert_eventually(live, "routing/instance_not_found")
      html = render(live)
      refute html =~ "enabling…"
      assert html =~ "watch Work / Vigil"
      refute has_element?(live, "#operations_subject")
    end
  end

  describe "with semantic-cache review scopes" do
    setup do
      scopes = ["agent.semantic_cache.read", "agent.semantic_cache.promote"]
      {:ok, spec: connected_endpoint(scopes: scopes)}
    end

    test "loads candidates and explicitly verifies one", %{conn: conn, spec: spec} do
      {:ok, live, html} = live(conn, agent_path(spec, :cache))
      assert html =~ "refresh candidates"

      live |> element("button", "refresh candidates") |> render_click()
      assert_eventually(live, "need a custom quote")

      html = render(live)
      assert html =~ "verify + promote"
      assert html =~ "quarantined"

      live |> element(~s(button[phx-click="verify"][phx-value-id="cache-1"])) |> render_click()
      assert_eventually(live, "example verified and promoted")

      html = render(live)
      assert html =~ "verified"
      refute html =~ "verify + promote"
    end
  end

  describe "with Journal access" do
    setup do
      {:ok, spec: connected_endpoint(scopes: ["ledger.read"])}
    end

    test "loads and renders bounded persisted turns", %{conn: conn, spec: spec} do
      {:ok, live, html} = live(conn, agent_path(spec, :journal))
      assert html =~ "turn journal"
      assert html =~ "no turns loaded"

      live
      |> form("#journal-form", %{
        "journal" => %{"subject" => "conversation-42", "limit" => "50"}
      })
      |> render_submit()

      assert_eventually(live, "show the latest article")
      html = render(live)
      assert html =~ "The latest article is Runtime Safety."
      assert html =~ "state revision 7"
      assert html =~ "2 turns"
    end

    test "discovers the active conversation and loads its Journal automatically", %{conn: conn} do
      spec =
        connected_endpoint(
          scopes: ["agent.runtime.read", "ledger.read"],
          instances: ["conversation-42"]
        )

      {:ok, live, _html} = live(conn, agent_path(spec, :journal))

      assert_eventually(live, "The latest article is Runtime Safety.")
      html = render(live)
      assert html =~ "live conversation"
      assert html =~ "subject conversation-42"
      assert html =~ "2 turns"
    end
  end

  describe "with Skill and Morph scopes" do
    setup do
      scopes = ["spectre.skill.read", "spectre.morph.propose"]
      {:ok, spec: connected_endpoint(scopes: scopes)}
    end

    test "lists Skills and creates an evaluated Morph proposal", %{
      conn: conn,
      spec: spec
    } do
      {:ok, live, html} = live(conn, agent_path(spec, :evolve))
      assert html =~ "Skill inventory"
      assert html =~ "create + evaluate proposal"

      live |> element("button", "refresh Skills") |> render_click()
      assert_eventually(live, "reader")
      assert render(live) =~ "refunds"

      live
      |> form("#morph-form", %{
        "morph" => %{
          "subject" => "account-1",
          "action" => "mount",
          "by" => "actor:operator",
          "reason" => "handle refunds",
          "mount_id" => "refund-helper",
          "match" => "refund",
          "reply" => "Refund request: {{input.text}}",
          "scopes" => "support",
          "token_cap" => "128"
        }
      })
      |> render_submit()

      assert_eventually(live, "evaluated")
      assert render(live) =~ "activated"
    end
  end

  defp agent_path(spec, tab \\ nil) do
    encoded = Agent.encode_address(@address)
    base = ~p"/connections/#{spec.id}/agents/#{encoded}"
    if tab, do: "#{base}/#{tab}", else: base
  end
end
