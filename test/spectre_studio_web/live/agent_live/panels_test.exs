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
    end

    test "monitoring starts only when asked, and streams once it does", %{conn: conn, spec: spec} do
      {:ok, live, html} = live(conn, agent_path(spec, :monitor))

      assert html =~ "not streaming"
      assert html =~ "enable live"

      html =
        live
        |> form("#monitor-form", %{
          "monitor" => %{"subject" => "account-1", "interval_ms" => "250", "duration_ms" => ""}
        })
        |> render_submit()

      # The subscription id is the host's to mint, so the control reports the
      # request in flight until the reply lands.
      assert html =~ "enabling…"
      refute html =~ "enable live"

      assert_receive {:monitor_enabled, _id, _request, subscription_id}, 5_000
      assert_receive {:monitor_update, _id, ^subscription_id, _subscription}, 5_000

      html = render(live)
      assert html =~ "disable live"
      assert html =~ "kB"
      assert html =~ "term-spark"
    end

    test "a subject is required to select an Instance", %{conn: conn, spec: spec} do
      {:ok, live, _html} = live(conn, agent_path(spec, :monitor))

      html =
        live
        |> form("#monitor-form", %{"monitor" => %{"subject" => "  "}})
        |> render_submit()

      assert html =~ "a subject is required"
    end

    test "leaving the monitor panel stops the stream", %{conn: conn, spec: spec} do
      {:ok, live, _html} = live(conn, agent_path(spec, :monitor))

      live
      |> form("#monitor-form", %{
        "monitor" => %{"subject" => "account-1", "interval_ms" => "250"}
      })
      |> render_submit()

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

    test "the live tab is absent, not disabled", %{conn: conn, spec: spec} do
      {:ok, _live, html} = live(conn, agent_path(spec))

      assert html =~ "overview"
      refute html =~ ">live<"
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

      {:ok, spec: connected_endpoint(scopes: scopes)}
    end

    test "streams publication-safe Work and Vigil snapshots", %{conn: conn, spec: spec} do
      {:ok, live, html} = live(conn, agent_path(spec, :operations))
      assert html =~ "not streaming"
      assert html =~ "watch Work / Vigil"

      live
      |> form("#operations-form", %{
        "operations" => %{
          "subject" => "account-1",
          "kinds" => "all",
          "interval_ms" => "250",
          "duration_ms" => ""
        }
      })
      |> render_submit()

      assert_receive {:operations_monitor_enabled, _id, _request, subscription_id}, 5_000
      assert_receive {:operations_monitor_update, _id, ^subscription_id, _subscription}, 5_000

      html = render(live)
      assert html =~ "research_pages"
      assert html =~ "cache_watch"
      assert html =~ "publication-safe bounded snapshot"
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

  describe "with Skill and Morph scopes" do
    setup do
      scopes = ["spectre.skill.runtime.mount", "spectre.morph.propose"]
      {:ok, spec: connected_endpoint(scopes: scopes)}
    end

    test "mounts a runtime Skill and creates an evaluated Morph proposal", %{
      conn: conn,
      spec: spec
    } do
      {:ok, live, html} = live(conn, agent_path(spec, :evolve))
      assert html =~ "create + mount Skill"
      assert html =~ "create + evaluate proposal"

      live
      |> form("#skill-form", %{
        "skill" => %{
          "subject" => "account-1",
          "mount_id" => "refunds",
          "definition" => ~s({"id":"refunds","declared_version":1})
        }
      })
      |> render_submit()

      assert_eventually(live, "mounted")

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
