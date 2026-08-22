defmodule SpectreStudioWeb.StudioComponents do
  @moduledoc """
  Domain widgets for the Studio control center.

  A control center displays things a document-oriented interface never has to:
  time series, saturation, and values that change every second. These components
  add that vocabulary to `SpectreStudioWeb.CoreComponents` without introducing a
  colour, radius or scale the visual language does not already use.

  The rules they implement are specified in `docs/UI.md`. Two are load-bearing
  and are enforced here rather than left to call sites:

    * a hued tone never carries meaning alone — every state renders a glyph and
      a word next to its colour;
    * an observation gap is drawn as a broken segment and never interpolated.
  """
  use Phoenix.Component

  @doc """
  Renders a status LED: glyph, colour and word, always together.

  ## Examples

      <.led state={:ok}>ready</.led>
      <.led state={:wait}>connecting</.led>
  """
  attr :state, :atom, values: [:ok, :fail, :wait, :idle], default: :idle
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block

  def led(assigns) do
    ~H"""
    <span class={["term-led", led_class(@state), @class]} {@rest}>
      <%= if @inner_block == [] do %>
        <span class="sr-only">{Atom.to_string(@state)}</span>
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </span>
    """
  end

  defp led_class(:ok), do: "term-led--ok"
  defp led_class(:fail), do: "term-led--fail"
  defp led_class(:wait), do: "term-led--wait"
  defp led_class(:idle), do: nil

  @doc """
  Renders one observed value.

  `value` is `nil` while nothing has been sampled yet; the metric then renders a
  blinking cursor instead of a number, because an empty panel and a panel
  reporting zero are different statements.
  """
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :unit, :string, default: nil
  attr :note, :string, default: nil
  attr :class, :any, default: nil

  def metric(assigns) do
    ~H"""
    <div class={["term-metric", is_nil(@value) && "term-metric--idle", @class]}>
      <span class="term-metric__label">{@label}</span>
      <span class="term-metric__value">
        <%= if is_nil(@value) do %>
          <span class="term-cursor" aria-hidden="true"></span>
          <span class="sr-only">no sample yet</span>
        <% else %>
          {@value}
          <span :if={@unit} class="term-metric__unit">{@unit}</span>
        <% end %>
      </span>
      <span :if={@note} class="term-metric__note">{@note}</span>
    </div>
    """
  end

  @doc """
  Renders a sparkline over a list of samples, oldest first.

  A `nil` entry is a hole in the observation, not a zero. Consecutive samples are
  drawn as a solid polyline; each hole becomes a dashed bridge between the
  surrounding runs, so the reader sees that the data is missing instead of
  reading an invented straight line as fact.
  """
  attr :samples, :list, default: []
  attr :label, :string, default: "series"
  attr :class, :any, default: nil

  def spark(assigns) do
    assigns = assign(assigns, :geometry, spark_geometry(assigns.samples))

    ~H"""
    <svg
      class={["term-spark", @class]}
      viewBox="0 0 100 24"
      preserveAspectRatio="none"
      role="img"
      aria-label={@label}
    >
      <%= if @geometry == :empty do %>
        <line class="term-spark__empty" x1="0" y1="12" x2="100" y2="12" />
      <% else %>
        <polyline :for={run <- @geometry.runs} class="term-spark__line" points={run} />
        <line
          :for={gap <- @geometry.gaps}
          class="term-spark__gap"
          x1={elem(gap, 0)}
          y1={elem(gap, 1)}
          x2={elem(gap, 2)}
          y2={elem(gap, 3)}
        />
        <rect
          :if={@geometry.head}
          class="term-spark__head"
          x={elem(@geometry.head, 0) - 1}
          y={elem(@geometry.head, 1) - 1}
          width="2"
          height="2"
        />
      <% end %>
    </svg>
    """
  end

  # Maps samples onto the 100x24 viewBox and splits them into solid runs and the
  # dashed bridges between them.
  defp spark_geometry(samples) do
    points = sample_points(samples)

    case Enum.filter(points, & &1) do
      [] -> :empty
      present -> %{runs: runs(points), gaps: gaps(points), head: List.last(present)}
    end
  end

  defp sample_points(samples) do
    values = Enum.filter(samples, &is_number/1)

    case values do
      [] ->
        []

      values ->
        {min, max} = Enum.min_max(values)
        span = if max == min, do: 1, else: max - min
        count = max(length(samples) - 1, 1)

        samples
        |> Enum.with_index()
        |> Enum.map(fn
          {value, index} when is_number(value) ->
            x = index / count * 100
            y = 22 - (value - min) / span * 20
            {Float.round(x, 2), Float.round(y, 2)}

          {_gap, _index} ->
            nil
        end)
    end
  end

  defp runs(points) do
    points
    |> Enum.chunk_by(&is_nil/1)
    |> Enum.reject(fn chunk -> chunk == [] or is_nil(hd(chunk)) end)
    |> Enum.map(fn chunk ->
      chunk |> Enum.map_join(" ", fn {x, y} -> "#{x},#{y}" end)
    end)
  end

  # One bridge per hole, drawn between the last known and the next known point.
  defp gaps(points) do
    points
    |> Enum.with_index()
    |> Enum.filter(fn {point, _index} -> is_nil(point) end)
    |> Enum.map(fn {_nil, index} ->
      {previous_point(points, index), next_point(points, index)}
    end)
    |> Enum.reject(fn {before, aft} -> is_nil(before) or is_nil(aft) end)
    |> Enum.map(fn {{x1, y1}, {x2, y2}} -> {x1, y1, x2, y2} end)
    |> Enum.uniq()
  end

  defp previous_point(points, index) do
    points |> Enum.take(index) |> Enum.reverse() |> Enum.find(& &1)
  end

  defp next_point(points, index) do
    points |> Enum.drop(index + 1) |> Enum.find(& &1)
  end

  @doc """
  Renders a saturation gauge with block characters.

  Used where a ratio matters more than a history — mailbox depth, subscription
  slots. A rounded progress bar would be the only such shape in the interface.
  """
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :cells, :integer, default: 16
  attr :threshold, :float, default: 0.8
  attr :label, :string, default: nil
  attr :class, :any, default: nil

  def gauge(assigns) do
    ratio = if assigns.max > 0, do: min(assigns.value / assigns.max, 1.0), else: 0.0
    filled = trunc(ratio * assigns.cells)
    half? = ratio * assigns.cells - filled >= 0.5 and filled < assigns.cells

    assigns =
      assigns
      |> assign(:filled, filled)
      |> assign(:half?, half?)
      |> assign(:empty, assigns.cells - filled - if(half?, do: 1, else: 0))
      |> assign(:saturated?, ratio >= assigns.threshold)

    ~H"""
    <div class={["term-gauge", @saturated? && "term-gauge--saturated", @class]}>
      <span :if={@label} class="t-dim">{@label}</span>
      <span class="term-gauge__bar" aria-hidden="true">
        <span class="term-gauge__fill">{String.duplicate("▓", @filled)}</span><span
          :if={@half?}
          class="term-gauge__half"
        >▒</span>{String.duplicate("░", @empty)}
      </span>
      <span class="term-gauge__value">{@value}/{@max}</span>
      <span :if={@saturated?} class="t-fail">saturated</span>
    </div>
    """
  end

  @doc """
  Renders the left navigation rail.
  """
  attr :class, :any, default: nil

  slot :group do
    attr :label, :string
  end

  slot :item do
    attr :navigate, :any
    attr :patch, :any
    attr :href, :any
    attr :current, :boolean
    attr :state, :atom
  end

  def rail(assigns) do
    ~H"""
    <nav class={["term-rail", @class]} aria-label="Studio sections">
      <div :for={group <- @group} class="term-rail__group">{group.label}</div>
      <.link
        :for={item <- @item}
        class="term-rail__item"
        aria-current={item[:current] && "page"}
        navigate={item[:navigate]}
        patch={item[:patch]}
        href={item[:href]}
      >
        <.led :if={item[:state]} state={item[:state]} class="!gap-0" />
        {render_slot(item)}
      </.link>
    </nav>
    """
  end

  @doc """
  Renders the tab strip of an Agent panel.

  A tab the operator is not authorised for is not rendered at all — not rendered
  disabled. An action that cannot be taken should not be present in the document.
  """
  attr :class, :any, default: nil

  slot :tab, required: true do
    attr :patch, :any
    attr :navigate, :any
    attr :selected, :boolean
  end

  def tabs(assigns) do
    ~H"""
    <div class={["term-tabs", @class]} role="tablist">
      <span class="term-tabs__sep" aria-hidden="true">[</span>
      <%= for {tab, index} <- Enum.with_index(@tab) do %>
        <span :if={index > 0} class="term-tabs__sep" aria-hidden="true">|</span>
        <.link
          class="term-tab"
          role="tab"
          aria-selected={to_string(!!tab[:selected])}
          patch={tab[:patch]}
          navigate={tab[:navigate]}
        >
          {render_slot(tab)}
        </.link>
      <% end %>
      <span class="term-tabs__sep" aria-hidden="true">]</span>
    </div>
    """
  end

  @doc """
  Renders the event stream of a connection or panel.

  Accepts a LiveView stream or a plain list of maps with `:id`, `:at`, `:kind`
  and `:text`. A live log belongs in a stream: the rows leave the server's
  memory after they are sent, and a new line costs one insert rather than a
  re-render of everything above it.

  The glyph reuses the shell prefixes: `$` for what Studio sent, `›` for what
  came back, `//` for a note, `!` for a failure.
  """
  attr :id, :string, required: true
  attr :events, :any, default: [], doc: "a LiveView stream or a list of event maps"
  attr :class, :any, default: nil

  def stream(assigns) do
    assigns = assign(assigns, :rows, stream_rows(assigns.events))

    ~H"""
    <div
      id={@id}
      class={["term-stream", @class]}
      phx-hook="StreamScroll"
      role="log"
      aria-live="polite"
    >
      <p class="term-comment py-2 t-faint" data-stream-empty>no events yet</p>
      <div id={"#{@id}-rows"} phx-update={if streamed?(@events), do: "stream"}>
        <div
          :for={{dom_id, event} <- @rows}
          id={dom_id}
          class={["term-stream__row", stream_row_class(event.kind)]}
        >
          <span class="term-stream__time">{format_time(event.at)}</span>
          <span class="term-stream__glyph" aria-hidden="true">{stream_glyph(event.kind)}</span>
          <span class="term-stream__text">{event.text}</span>
        </div>
      </div>
    </div>
    """
  end

  defp streamed?(%Phoenix.LiveView.LiveStream{}), do: true
  defp streamed?(_events), do: false

  defp stream_rows(%Phoenix.LiveView.LiveStream{} = stream), do: stream

  defp stream_rows(events) when is_list(events) do
    Enum.map(events, fn event -> {Map.get(event, :id, "event-#{inspect(event.at)}"), event} end)
  end

  defp stream_row_class(:sent), do: "term-stream__row--sent"
  defp stream_row_class(:note), do: "term-stream__row--note"
  defp stream_row_class(:fail), do: "term-stream__row--fail"
  defp stream_row_class(_received), do: nil

  defp stream_glyph(:sent), do: "$"
  defp stream_glyph(:note), do: "//"
  defp stream_glyph(:fail), do: "!"
  defp stream_glyph(_received), do: "›"

  @doc "Formats a timestamp for the event stream."
  def format_time(%DateTime{} = at), do: Calendar.strftime(at, "%H:%M:%S")

  def format_time(unix_ms) when is_integer(unix_ms) do
    unix_ms |> DateTime.from_unix!(:millisecond) |> format_time()
  end

  def format_time(_other), do: "--:--:--"

  @doc """
  Renders one row of a comparison.

  The outcome tone sits on the glyph alone. A long diff must stay readable as
  text, not become a wall of colour.
  """
  attr :kind, :atom, values: [:added, :removed, :changed, :same], default: :same
  attr :class, :any, default: nil

  slot :inner_block, required: true

  def diff_row(assigns) do
    ~H"""
    <div class={["term-diff__row", diff_row_class(@kind), @class]}>
      <span class="term-diff__glyph" aria-hidden="true">{diff_glyph(@kind)}</span>
      <span class="term-diff__text">
        <span class="sr-only">{Atom.to_string(@kind)}:</span>{render_slot(@inner_block)}
      </span>
    </div>
    """
  end

  defp diff_row_class(:added), do: "term-diff__row--added"
  defp diff_row_class(:removed), do: "term-diff__row--removed"
  defp diff_row_class(:changed), do: "term-diff__row--changed"
  defp diff_row_class(:same), do: nil

  defp diff_glyph(:added), do: "+"
  defp diff_glyph(:removed), do: "-"
  defp diff_glyph(:changed), do: "~"
  defp diff_glyph(:same), do: " "

  @doc """
  Renders one permission scope.

  A withheld scope is shown rather than hidden, so the operator can see why a
  panel is unavailable instead of wondering whether Studio is broken.
  """
  attr :scope, :string, required: true
  attr :granted, :boolean, default: true
  attr :class, :any, default: nil

  def scope_badge(assigns) do
    ~H"""
    <span
      class={["term-chip", !@granted && "term-chip--withheld", @class]}
      title={if @granted, do: "granted", else: "not granted by this connection"}
    >
      {@scope}<span :if={!@granted} class="sr-only">— not granted</span>
    </span>
    """
  end
end
