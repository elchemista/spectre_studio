defmodule SpectreStudioWeb.CoreComponentsTest do
  @moduledoc """
  Every core component must speak the terminal language.

  These are not redundant with the visual spec: a component that quietly falls
  back to browser defaults looks like a broken application, and that is exactly
  what is easy to miss when a component is rarely rendered.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import SpectreStudioWeb.CoreComponents

  test "term_window frames content with a title bar" do
    html =
      render_component(&term_window/1,
        title: "manifest",
        status: "ready",
        inner_block: block("body")
      )

    assert html =~ "term-window"
    assert html =~ "term-bar"
    assert html =~ "term-dot"
    assert html =~ "manifest"
    assert html =~ "ready"
  end

  test "flash notices are terminal windows, not browser defaults" do
    html = render_component(&flash/1, kind: :info, flash: %{"info" => "Connection saved."})

    assert html =~ "term-flash"
    assert html =~ "term-window"
    assert html =~ "term-bar"
    assert html =~ "stdout"
    assert html =~ "Connection saved."
    # Dismissal is part of the language too: [x], not a stray unstyled button.
    assert html =~ "[x]"
  end

  test "an error flash names the stream it came from" do
    html = render_component(&flash/1, kind: :error, flash: %{"error" => "boom"})

    assert html =~ "stderr"
    assert html =~ "term-window"
    assert html =~ "boom"
  end

  test "a flash with nothing to say renders nothing" do
    assert render_component(&flash/1, kind: :info, flash: %{}) =~ ~r/\A\s*\z/
  end

  test "buttons carry the terminal button style" do
    assert render_component(&button/1, inner_block: block("send")) =~ "term-btn"

    primary = render_component(&button/1, variant: "primary", inner_block: block("send"))
    assert primary =~ "term-btn--primary"

    link = render_component(&button/1, navigate: "/", inner_block: block("home"))
    assert link =~ "term-btn"
    assert link =~ ~s(href="/")
  end

  test "text inputs carry the field and label styles" do
    html = render_component(&input/1, name: "label", value: "", label: "label", id: "x")

    assert html =~ "term-field"
    assert html =~ "term-label"
  end

  test "a checkbox is drawn as an ASCII toggle" do
    html =
      render_component(&input/1,
        type: "checkbox",
        name: "tls",
        value: "true",
        label: "tls",
        id: "x"
      )

    assert html =~ "term-check"
    assert html =~ "term-check__box"
  end

  test "a select draws its own arrow" do
    html =
      render_component(&input/1,
        type: "select",
        name: "act",
        value: "inform",
        label: "act",
        id: "x",
        options: [{"inform", "inform"}]
      )

    assert html =~ "term-select"
    assert html =~ "term-field"
  end

  test "a textarea keeps the field style" do
    html =
      render_component(&input/1,
        type: "textarea",
        name: "data",
        value: "{}",
        label: "data",
        id: "x"
      )

    assert html =~ "term-field"
    assert html =~ "term-label"
  end

  test "field errors are marked in the terminal palette" do
    html = render_component(&input/1, name: "url", value: "", id: "x", errors: ["is invalid"])

    assert html =~ "term-field--error"
    assert html =~ "is invalid"
  end

  test "the header rules itself off with a dashed line" do
    html =
      render_component(&header/1,
        inner_block: block("connections"),
        subtitle: block("every system"),
        actions: block("action")
      )

    assert html =~ "border-dashed"
    assert html =~ "t-strong"
    assert html =~ "t-faint"
    assert html =~ "connections"
  end

  test "tables and lists use the terminal treatments" do
    table =
      render_component(&table/1,
        id: "agents",
        rows: [%{name: "researcher"}],
        col: [%{label: "name", inner_block: fn _a, row -> row.name end}]
      )

    assert table =~ "term-table"
    assert table =~ "researcher"

    list =
      render_component(&list/1, item: [%{title: "address", inner_block: fn _a, _s -> "x" end}])

    assert list =~ "term-list"
    assert list =~ "term-list__key"
  end

  test "the cursor blinks and the icon inherits the current tone" do
    assert render_component(&cursor/1, []) =~ "term-cursor"
    assert render_component(&icon/1, name: "hero-sun") =~ "hero-sun"
  end

  defp block(text) do
    [%{inner_block: fn _assigns, _slot -> text end, __slot__: :inner_block}]
  end
end
