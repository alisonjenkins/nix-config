# Contract: cortexiphan export (FR-023 to FR-029, SC-009)

`claude-monitor export cortexiphan` writes **JSON Lines**, UTF-8, one record per line, sorted by `(kind, external.id)` so two exports of unchanged data are byte-identical. `schema_version` bumps only for breaking changes; fields are added, never repurposed (mirrors cortexiphan V8, additive wire evolution).

The ingest side does not exist in cortexiphan yet (no file import; MCP `node_create` rejects projects; the CLI only creates notes and tasks). This contract is what the future ingest reads; cortexiphan owns the loader. Until then the file is also the human-readable backup.

## Record envelope

```json
{
  "schema_version": 1,
  "kind": "project | task | memory | session | edge",
  "external": { "system": "ai-control-centre", "id": "<uuid>", "url": null },
  "author": { "type": "user | llm | connector", "name": "alison | claude-opus-5-5 | ai-control-centre" },
  "updated_at": "2026-10-12T14:03:22Z",
  "node": { }
}
```

`external` is the idempotency key: a loader upserts on `(system, id)` as cortexiphan's connector `ExpandConnectorNode` does, so re-import creates no duplicates. `author.type` maps to cortexiphan `Author::User | Llm{model} | Connector{name}`; the author is the last event's author for that entity, and the full list is in the optional `history` array.

## `node` by kind

**project** (→ `NodeKind::Project`, `ProjectFields`)

```json
{ "title": "ai-control-centre", "status": "active|paused|done|archived",
  "repos": [ { "name": "nix-config", "uri": "git@github.com:…", "clones": [ { "machine": "ali-desktop", "path": "/home/ali/git/personal/nix-config" } ] } ] }
```

**task** (→ `NodeKind::Task`, `TaskFields`) — one per progress step

```json
{ "title": "T005 Add liveness probe", "status": "todo|doing|done|blocked", "part_of": "<project external.id>", "source": "specs/008-ai-control-centre/tasks.md" }
```

**memory** (→ `NodeKind::Memory`) — notes and model-written summaries; summaries carry `"model_written": true`

```json
{ "body": "…", "about": "<project or session external.id>" }
```

**session** (→ `NodeKind::Custom{kind:"session", fields}`)

```json
{ "agent_kind": "claude", "agent_session_id": "…", "cwd": "…", "branch": "…", "state": "interrupted",
  "last_activity_at": "…", "done_at": "…|null", "resumed_from": "<session external.id>|null", "project": "<project external.id>|null" }
```

Conversation text (prompts, assistant messages, transcripts) is never exported; `task_description` and `left_off` are omitted by default and included only with `--include-text`.

**edge** — `{ "from": "<external.id>", "to": "<external.id>", "type": "part_of | resumed_from" }`.

## Status mapping

| Control centre | Cortexiphan |
|---|---|
| project `active` / `parked` / `done` / `archived` | `ProjectStatus::Active` / `Paused` / `Done` / `Archived` |
| step `todo` / `doing` / `done` / `blocked` | `TaskStatus::Todo` / `Doing` / `Done` / `Blocked` |
| event author `user` / `agent` / `system` | `Author::User` / `Llm{model}` / `Connector{name}` |

## Links and conflicts (FR-026, FR-028)

A `CortexiphanLink` row pairs a local id with a cortexiphan `NodeId`. `links check` reads the remote status via `cortexiphan --json node get` only when `CORTEXIPHAN_SERVER` and a token are configured; it reports, per link, local status, remote status and `last_agreed_at`. It never writes to either side. Resolution is the user's choice by re-running export (local wins) or editing locally (remote wins); nothing is applied automatically.

## Versioning and tests

- `contracts/cortexiphan-export.schema.json` (JSON Schema, generated from the Rust types and checked in; a test fails if they diverge) is the machine-readable form.
- Golden-file test: a fixed project with 20 steps exports to a checked-in file; any change to it is a reviewed schema change.
- Round trip: export → parse → re-export is byte-identical.
