defmodule SpectreStudioWeb.StudioComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import SpectreStudioWeb.StudioComponents

  describe "led/1" do
    test "a state is never colour alone" do
      html = render_component(&led/1, state: :ok, inner_block: block("ready"))

      assert html =~ "term-led--ok"
      assert html =~ "ready"
    end

    test "a bare LED still names its state for a screen reader" do
      html = render_component(&led/1, state: :fail)

      assert html =~ "term-led--fail"
      assert html =~ ~s(<span class="sr-only">fail</span>)
    end
  end

  describe "metric/1" do
    test "an unsampled metric shows a cursor, not a zero" do
      html = render_component(&metric/1, label: "memory", value: nil)

      assert html =~ "term-metric--idle"
      assert html =~ "term-cursor"
      assert html =~ "no sample yet"
      refute html =~ ">0<"
    end

    test "a sampled metric separates value from unit" do
      html = render_component(&metric/1, label: "heap", value: "2 584", unit: "words")

      assert html =~ "2 584"
      assert html =~ ~s(class="term-metric__unit">words)
    end
  end

  describe "spark/1" do
    test "an empty series draws a baseline rather than nothing" do
      html = render_component(&spark/1, samples: [])

      assert html =~ "term-spark__empty"
      refute html =~ "term-spark__line"
    end

    test "a continuous series is one solid polyline" do
      html = render_component(&spark/1, samples: [1, 2, 3, 4])

      assert html =~ "term-spark__line"
      refute html =~ "term-spark__gap"
      assert html =~ "term-spark__head"
    end

    test "a hole in the observation is drawn as a break, never interpolated" do
      html = render_component(&spark/1, samples: [1, 2, nil, 4, 5])

      # Two solid runs and one dashed bridge: the reader sees the samples are
      # missing instead of reading an invented straight line as measurement.
      assert html =~ "term-spark__gap"
      assert length(String.split(html, "term-spark__line")) - 1 == 2
    end
  end

  describe "gauge/1" do
    test "reports saturation in words as well as tone" do
      html = render_component(&gauge/1, value: 15, max: 16, label: "mailbox")

      assert html =~ "term-gauge--saturated"
      assert html =~ "saturated"
      assert html =~ "15/16"
    end

    test "stays quiet below the threshold" do
      html = render_component(&gauge/1, value: 1, max: 16)

      refute html =~ "term-gauge--saturated"
      refute html =~ "saturated"
    end
  end

  describe "diff_row/1" do
    test "the outcome lives on the glyph, not on the background" do
      html = render_component(&diff_row/1, kind: :added, inner_block: block("revision 4"))

      assert html =~ "term-diff__row--added"
      assert html =~ "+"
      assert html =~ "revision 4"
    end
  end

  describe "scope_badge/1" do
    test "a withheld scope is shown, not hidden" do
      html = render_component(&scope_badge/1, scope: "lab.read", granted: false)

      assert html =~ "term-chip--withheld"
      assert html =~ "lab.read"
      assert html =~ "not granted"
    end
  end

  describe "stream/1" do
    test "each kind carries its own shell prefix" do
      events = [
        %{at: ~U[2026-08-22 12:04:31Z], kind: :sent, text: "monitor.enable"},
        %{at: ~U[2026-08-22 12:04:32Z], kind: :received, text: "enabled"},
        %{at: ~U[2026-08-22 12:04:33Z], kind: :note, text: "coalesced"},
        %{at: ~U[2026-08-22 12:04:34Z], kind: :fail, text: "instance_not_found"}
      ]

      html = render_component(&stream/1, id: "events", events: events)

      assert html =~ "12:04:31"
      assert html =~ "term-stream__row--sent"
      assert html =~ "term-stream__row--note"
      assert html =~ "term-stream__row--fail"
      assert html =~ "$"
      assert html =~ "›"
    end

    test "an empty stream says so" do
      html = render_component(&stream/1, id: "events", events: [])
      assert html =~ "no events yet"
    end
  end

  defp block(text) do
    [%{inner_block: fn _assigns, _slot -> text end, __slot__: :inner_block}]
  end
end
