defmodule SpectreStudioWeb.ConnectionLive.FormTest do
  use SpectreStudioWeb.ConnCase, async: false

  alias SpectreStudio.Pulse
  alias SpectreStudio.Vault

  setup do
    on_exit(fn -> Enum.each(Vault.list(), &Pulse.delete(&1.id)) end)
    :ok
  end

  test "creating a connection lands on it", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/connections/new")

    live
    |> form("#connection-form", %{
      "connection" => %{
        "label" => "prod-eu",
        "url" => "wss://host/pulse/websocket",
        "token" => "super-secret"
      }
    })
    |> render_submit()

    assert {path, flash} = assert_redirect(live)
    assert path =~ "/connections/"
    assert flash["info"] =~ "prod-eu"

    # The credential never comes back out.
    {:ok, _live, html} = live(conn, path)
    refute html =~ "super-secret"
  end

  test "a malformed endpoint is rejected with a reason", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/connections/new")

    html =
      live
      |> form("#connection-form", %{"connection" => %{"label" => "", "url" => "https://host"}})
      |> render_submit()

    assert html =~ "is required"
    assert html =~ "must be a ws:// or wss:// URL"
  end

  test "editing pre-fills the stored spec", %{conn: conn} do
    {:ok, spec} = Pulse.save(%{"label" => "staging", "url" => "wss://host/pulse"})

    {:ok, _live, html} = live(conn, ~p"/connections/#{spec.id}/edit")

    assert html =~ "staging"
    assert html =~ "wss://host/pulse"
    assert html =~ "edit connection"
  end

  test "editing a connection that is gone returns to the dashboard", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/connections/missing/edit")
  end
end
