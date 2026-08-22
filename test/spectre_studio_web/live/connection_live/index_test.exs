defmodule SpectreStudioWeb.ConnectionLive.IndexTest do
  use SpectreStudioWeb.ConnCase, async: false

  alias SpectreStudio.Pulse
  alias SpectreStudio.Vault

  setup do
    on_exit(fn -> Enum.each(Vault.list(), &Pulse.delete(&1.id)) end)
    :ok
  end

  test "launching Studio opens the dashboard, with nothing in the way", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ "term-rail"
    assert html =~ "every Spectre system this Studio can reach"
    refute html =~ "password"
    refute html =~ "login"
  end

  test "the dashboard also answers on its old address", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/connections")
    assert html =~ "every Spectre system this Studio can reach"
  end

  test "the empty state speaks the shell's language", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ "no connections configured"
    assert html =~ "./new-connection"
  end

  test "endpoints render as stream entries", %{conn: conn} do
    {:ok, spec} = Pulse.save(%{"label" => "prod-eu", "url" => "wss://host/pulse"})

    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ ~s(id="endpoints")
    assert html =~ ~s(phx-update="stream")
    assert html =~ ~s(id="endpoints-#{spec.id}")
    assert html =~ "prod-eu"
  end

  test "an unverified endpoint is labelled as such", %{conn: conn} do
    {:ok, _spec} =
      Pulse.save(%{
        "label" => "local",
        "url" => "ws://localhost:4444/pulse",
        "verify_tls" => "false"
      })

    {:ok, _live, html} = live(conn, ~p"/")
    assert html =~ "UNVERIFIED"
  end

  test "removing a connection drops only its row", %{conn: conn} do
    {:ok, kept} = Pulse.save(%{"label" => "kept", "url" => "wss://host/pulse"})
    {:ok, doomed} = Pulse.save(%{"label" => "doomed", "url" => "wss://host/pulse"})

    {:ok, live, _html} = live(conn, ~p"/")

    html =
      live
      |> element("button[phx-click='delete'][phx-value-id='#{doomed.id}']")
      |> render_click()

    refute html =~ "doomed"
    assert html =~ "kept"
    assert html =~ ~s(id="endpoints-#{kept.id}")
    assert Vault.fetch(doomed.id) == :error
  end
end
