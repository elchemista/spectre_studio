defmodule SpectreStudioWeb.ErrorHTMLTest do
  use SpectreStudioWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html in the terminal shell" do
    html = render_to_string(SpectreStudioWeb.ErrorHTML, "404", "html", [])

    assert html =~ "Not found"
    assert html =~ "term-window"
    assert html =~ "./dashboard"
  end

  test "renders 500.html without leaking internals" do
    html = render_to_string(SpectreStudioWeb.ErrorHTML, "500", "html", [])

    assert html =~ "Internal server error"
    assert html =~ "term-window"
    assert html =~ "in the server log"
  end

  test "the endpoint actually serves the styled page for an unknown route", %{conn: conn} do
    body = conn |> get("/nope") |> html_response(404)

    assert body =~ "term-window"
    assert body =~ "Not found"
    assert body =~ "site-shell"
  end

  test "an unknown status still wears the shell" do
    html = render_to_string(SpectreStudioWeb.ErrorHTML, "503", "html", [])

    assert html =~ "Service Unavailable"
    assert html =~ "term-window"
  end
end
