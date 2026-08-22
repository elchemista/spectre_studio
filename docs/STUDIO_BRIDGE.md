# The Studio bridge

Pulse carries the connection and its technical events. It does not implement
Ledger queries, `lab.playback` or `lab.diff` — those belong to their own
libraries, and Pulse says so explicitly. So when Studio needs something that is
not runtime monitoring, it asks the **host application** for it, over the Pulse
socket, as an ordinary envelope.

This document is that contract. Implement it and the Ledger panels open. Leave
it unimplemented and Studio keeps them closed with a stated reason, rather than
failing in a way that looks like a bug.

## Status

Not implemented in Studio yet. The Lab panel currently works from operator
uploads only. This file defines the shape the bridge will take, so a host can
be built against it and so the reason a panel is missing is written down.

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

## Authorisation

These are application scopes. Pulse enforces only `agent.runtime.read` and
`agent.runtime.stream`; it will transport these envelopes regardless. The host
must therefore check them itself, in its `authorize/2` callback and again when
it handles the payload:

```elixir
scopes: [
  "agent.runtime.read",
  "agent.runtime.stream",
  "ledger.read",
  "lab.read"
]
```

Studio shows a panel only when the manifest lists the matching scope. That is a
statement of intent, not a boundary — the boundary stays with the host.

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
