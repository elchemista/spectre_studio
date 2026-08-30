# The Studio bridge

Studio sends scoped inspection and governance requests as ordinary Pulse
envelopes. Current Spectre Pulse handles these requests at the authenticated
connection boundary, so they never become Agent prompts or application turns.

## Active Instance discovery

Studio requests `agent.instances.list` when Live, Work/Vigil, or Journal opens.
When Pulse returns at least one authorized live Instance, Studio selects its
subject automatically: Live and Work/Vigil start streaming, while Journal loads
the persisted turns and reloads when an Agent event for that subject arrives.
The manual Journal subject remains available for an inactive conversation.

Discovery requires `agent.runtime.read` and is limited to Agents exposed by the
Pulse connection. Journal remains independently protected by `ledger.read`, and
the streaming panels still require their own `*.stream` grants. Removing any
scope from the host connection locks that surface and makes Pulse reject direct
requests too.

## Available panels

| Studio panel | Pulse payload | Required scope |
| --- | --- | --- |
| Semantic cache review | `studio.semantic_cache.examples` | `agent.semantic_cache.read` |
| Edit mutable cache row | `studio.semantic_cache.update` | `agent.semantic_cache.write` |
| Verify + promote cache row | `studio.semantic_cache.verify` | `agent.semantic_cache.promote` |
| Journal / turns | `studio.journal.turns` | `ledger.read` |
| Skill inventory | `studio.skills.list` | `spectre.skill.read` |
| New governed Skill proposal | `studio.morph.propose_skill` | `spectre.morph.propose` |

The host must run a Pulse version that includes `Spectre.Pulse.Studio`, list the
scope in its connection specification, allow it on the authenticated principal,
and return it from `authorize/2`. Studio cannot infer or grant a missing scope.

```elixir
scopes = [
  "agent.runtime.read",
  "agent.runtime.stream",
  "agent.operations.read",
  "agent.operations.stream"
] ++ Spectre.Pulse.Studio.scopes()
```

Every successful reply uses the request type plus `.result`; a safe failure uses
`.error`. Both correlate through `relates_to`. A Pulse receipt means only that
the transport accepted the envelope.

## What each operation means

Semantic-cache editing calls the configured Spectre cache boundary and only
accepts categories exposed by the Agent's cacheable routes. Only mutable
online-learned rows may be changed; dataset and other static rows remain
read-only. Editing does not verify a row.

Semantic-cache verification is a separate operation. For the learned cache,
verification is also promotion: the quarantined row becomes eligible for
normal lookup.

Journal/turns reads the bounded compact chat history from the Agent's persisted
state. It is not the Studio connection event log, raw memory, or a complete
audit ledger. Its subject is the persistence conversation id.

Skill inventory projects the mounts compiled into the current Agent Definition.
New runtime Skills are authored as Morph proposals. Studio creates/evaluates a
reply-only candidate but cannot approve or activate it; those are separate host
governance commits. Direct arbitrary JSON mounting is intentionally not exposed
because Studio does not own the runtime Authority Envelope or revision fence.

## Diagnosing locked or empty panels

- A locked tab means the manifest does not contain its required scope. Hovering
  the tab and the Overview capability matrix show the exact missing grant.
- `capabilities —` means the remote Agent descriptor advertised no capabilities;
  Studio does not fabricate them from the Agent address.
- A panel that opens but returns an authorization error usually means the host
  manifest and deployed Pulse/authorization policy disagree.
- Connection events show the request, receipt, correlated result/error, and
  reconnect lifecycle separately.

## Safety boundary

Pulse resolves only an Agent already exposed on that authenticated connection.
It creates no module atom from remote input, bounds row and text counts, and
projects only publication-safe fields. OTP monitoring is separate and never
includes mailbox contents, process dictionaries or GenServer state.

Lab bundle export and full Ledger chain/usage views are not part of this bridge.
Those require their own extension-specific contracts rather than a general RPC
escape hatch.
