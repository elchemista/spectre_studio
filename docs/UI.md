# Studio UI guide

Studio uses a compact terminal-style interface for connections, runtime metrics
and offline analysis. The visual system is implemented in this application.

## Source map

| File | Responsibility |
| --- | --- |
| [`assets/css/app.css`](../assets/css/app.css) | Themes, shared tokens, terminal components and responsive styles |
| [`core_components.ex`](../lib/spectre_studio_web/components/core_components.ex) | Forms, inputs, buttons, flashes and common controls |
| [`studio_components.ex`](../lib/spectre_studio_web/components/studio_components.ex) | Metrics, navigation, scopes, streams and diffs |
| [`layouts.ex`](../lib/spectre_studio_web/components/layouts.ex) | Shared application shell |
| [`app.js`](../assets/js/app.js) | LiveView setup and browser behavior |

## Visual rules

Use the shared monospace font and tone tokens rather than literal colors in
markup. `--fg-strong`, `--fg`, `--fg-dim` and `--fg-faint` establish hierarchy;
`--surface*` and `--line*` define panels and boundaries. Dark and light themes
use the same token names. Code blocks retain a dark background in either theme.

Color indicates status: `--state-ok`, `--state-fail` and `--state-wait`. Pair it
with text or a glyph so the meaning survives without color. Changing numbers
use tabular digits; units remain separate from the value.

Panels use `.term-window` with a `.term-bar`. Labels follow the terminal
vocabulary: `$` for commands, `›` for replies and `//` for system notes. Keep
transitions subtle and respect reduced-motion preferences.

## Shared components

| Component | Use |
| --- | --- |
| `led/1` | Connection or process status with an accessible label |
| `metric/1` | Current measurement, delta and loading state |
| `spark/1` | Bounded measurement series with visible observation gaps |
| `gauge/1` | Capacity or backpressure ratio |
| `rail/1` | Main navigation and current location |
| `tabs/1` | Agent panels, including locked capabilities |
| `stream/1` | Bounded connection/event output |
| `diff_row/1` | Added, removed and changed rows |
| `scope_badge/1` | Granted or withheld host scopes |

Tabs stay visible when a host withholds their scope. A locked tab is disabled
and explains the missing grant; Overview shows the same capability matrix.
The remote host still authorizes every request. A visible tab never grants
permission by itself. See [the bridge contract](STUDIO_BRIDGE.md).

## Live data and failure states

Missing data is displayed as missing, rather than as zero. Sparklines show gaps
in observation without inventing intermediate samples. A stream disconnect
keeps its observed data and reports the error; it does not turn the stream into
durable history.

Keep empty, loading, locked and failed states distinct. Work that may take time
runs through LiveView async operations and exposes its pending state. Growing
lists use LiveView streams rather than unbounded assigns.

Each panel is a separate LiveView. Runtime subscriptions belong to the active
panel and stop when it closes; offline Lab views use their own bundle data.
These panels currently target the retained Instance bridge described in the
[README](../README.md#spectre-compatibility).

## Accessibility and review

Keep visible focus indicators, semantic table headings, labels and keyboard
navigation. Status must include words as well as color; decorative glyphs use
`aria-hidden`, while navigation identifies its current item. Live output uses
polite announcements rather than announcing every metric sample.

Review UI changes in both themes and a narrow viewport, including empty,
loading, error and missing-scope states. Protocol and authorization behavior
belongs in the bridge guide rather than in visual styling rules.
