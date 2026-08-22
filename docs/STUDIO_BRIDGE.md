# The Studio bridge

Pulse carries the connection and its technical events. It does not implement
Ledger queries, `lab.playback` or `lab.diff` — those belong to their own
libraries, and Pulse says so explicitly. So when Studio needs something that is
not runtime monitoring, it asks the **host application** for it, over the Pulse
socket, as an ordinary envelope.

This document is that contract. Implemented cache, Skill and Morph operations
open their Agent panels; the Ledger operations define the next consumers.
Leave an operation unimplemented and the host should return its typed `.error`
reply rather than failing in a way that looks like a transport bug.

## Status

Implemented in Studio for semantic-cache review, runtime Skill mounting and
Morph proposal authoring. Ledger and remote Lab consumers still remain to be
built. The host side is intentionally application-owned: Pulse authenticates
and transports the envelope, while the host resolves the Agent/Instance and
executes the domain API under its own authorization policy.

## Shape

Every call is an ordinary Pulse envelope. Studio sends `act: :query`, the host
replies with `act: :inform` and `relates_to` set to the request id.

```json
{
  "version": 1,
  "id": "019...",
  "from": "spectre://studio/operator-42",
  "to": "spectre://acme/researcher",
  "act": "query",
  "payload": {
    "type": "studio.ledger.head",
    "data": { "subject": "account-123" }
  }
}
```

## Operations

| Payload type | Data | Reply | Unlocks |
| --- | --- | --- | --- |
| `studio.agent.subjects` | `{}` | `{"subjects": ["account-123", …]}` | Subject picker in the live panel |
| `studio.ledger.head` | `{"subject": …}` | `{"revision": n, "entry_digest": …}` | Ledger panel header |
| `studio.ledger.entries` | `{"subject": …, "limit": n}` | `{"entries": [...]}` | Chain view |
| `studio.ledger.inference_usage` | `{"subject": …}` | `{"usage": {...}}` | Token and model totals |
| `studio.ledger.bundle.export` | `{"subject": …}` | `{"bundle": "<base64>"}` | Lab playback and diff without a manual upload |
| `studio.semantic_cache.examples` | `{"source": "online_learned"}` | `{"examples": [...]}` | Per-Agent review queue |
| `studio.semantic_cache.verify` | `{"example_id": …}` | `{"example": {...}}` | Explicit verification and promotion |
| `studio.skill.mount` | `{"subject": …, "mount_id": …, "definition": {...}}` | `{"status": "mounted", "revision": n}` | New runtime Skill |
| `studio.morph.propose_skill` | Morph fields below | Morph status + report | Governed Skill proposal and evaluation |

Every successful reply uses the request type plus `.result`; every safe
failure uses `.error`. The reply is an `inform` envelope whose `relates_to`
equals the request id. A Pulse transport receipt only means that the host
accepted the envelope; it is not the operation result.

### Semantic cache

`studio.semantic_cache.verify` maps to
`Spectre.Router.SemanticCache.verify/3`. For the built-in learned cache this is
also the promotion step: it sets `verified?: true`, records `verified_at`, and
makes the row eligible for normal lookup. Studio deliberately calls the action
**verify + promote** so the operational effect is visible.

The host resolves the canonical Pulse address to a known Agent module. It must
never create a module atom from the remote address or another client string.

### Runtime Skill mount

The host validates `definition` with `Spectre.Skill.Definition.new/1`, obtains
the application-owned `Spectre.Skill.Runtime`, and calls
`Spectre.Skill.Runtime.mount/4` with its current expected revision. Studio does
not own the Authority Envelope or cache a copy of the runtime.

### Morph proposal

The request contains:

```json
{
  "subject": "account-123",
  "action": "mount",
  "by": "actor:studio",
  "reason": "Serve refund questions",
  "mount_id": "refunds",
  "match": "refund",
  "reply": "Refund request: {{input.text}}",
  "scopes": ["support"],
  "token_cap": 128
}
```

The host resolves the Instance and runs `Spectre.Morph.change/2`, followed by
`mount_skill/3` or `replace_skill/3`, then `evaluate/2`. This operation stops
there. It does **not** approve or activate the candidate; those are separate
human/host governance commits and are intentionally absent from this Studio
surface.

## Authorisation

These are application scopes. Pulse enforces only `agent.runtime.read` and
`agent.runtime.stream`; it will transport these envelopes regardless. The host
must therefore check them itself, in its `authorize/2` callback and again when
it handles the payload:

```elixir
scopes: [
  "agent.runtime.read",
  "agent.runtime.stream",
  "agent.operations.read",
  "agent.operations.stream",
  "agent.semantic_cache.read",
  "agent.semantic_cache.promote",
  "spectre.skill.runtime.mount",
  "spectre.morph.propose",
  "ledger.read",
  "lab.read"
]
```

Studio shows a panel only when the manifest lists the matching scope. That is a
statement of intent, not a boundary — the boundary stays with the host.

The runtime and operations scope pairs are enforced by Pulse itself. The
semantic-cache, Skill and Morph scopes are application scopes and therefore
must be checked again by the host handler before it invokes Spectre.

## The bundle export is a privileged operation

A Ledger bundle is a trusted artefact: Foundation decoding may load an existing
module named by a valid checkpoint. `studio.ledger.bundle.export` therefore
hands a caller something closer to code than to data.

- gate it behind its own scope, not behind `ledger.read`;
- consider it equivalent to granting read access to persisted agent state;
- do not expose it on a connection whose principal you would not trust with a
  production checkpoint.

## What the bridge is not

- It is not a way to make Pulse own Lab or Ledger. The operations live in the
  host; Pulse only carries them.
- It is not a general RPC surface. Every payload type here answers one question
  a Studio panel asks, and nothing else.
- It does not extend runtime monitoring. Token totals, model calls and memory
  records are Ledger's, and they never appear in a `monitor.update`.
