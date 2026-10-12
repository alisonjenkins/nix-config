# Data Model: AI Control Centre

Store: one SQLite database (see research D1). All timestamps are RFC 3339 UTC text (`2026-10-12T14:03:22Z`). All ids are text. Projections are rebuilt from `events` if lost; `events` is the source of truth for changes and attribution.

## Entities

### Session  (spec: Session, Worktree Location)

| Field | Type | Notes |
|---|---|---|
| `id` | text PK | Internal id (UUID v4). Stable across respawns of the same logical work. |
| `agent_kind` | text | `claude` \| `copilot` \| future kinds |
| `agent_session_id` | text | The agent's own conversation id (`session_id` / Copilot UUID). Unique per `(agent_kind, agent_session_id)`. |
| `resumed_from` | text FK Session.id, null | Lineage predecessor, set only when a `RespawnRequest` of ours produced this session (FR-011). The overview shows the head of a chain. |
| `forked_from` | text FK Session.id, null | Set when a new conversation derives from an existing one without our respawn (for example a fork). A fork starts its own chain and is never collapsed into the original's head (spec edge case "genuinely separate fork"). Detection details follow the R1 spike. |
| `repo_root` | text, null | Git top level of `cwd` at last sight |
| `cwd` | text | Working directory the agent ran in; the respawn target |
| `branch` | text, null | Branch at last sight |
| `worktree_exists` | int | Refreshed by reconcile; drives "no valid location" flag |
| `state` | text | See state machine |
| `end_reason` | text, null | Raw agent reason code (`clear`, `logout`, `prompt_input_exit`, `complete`, `error`, ...) |
| `task_description` | text, null | First prompt, full text (view truncates) |
| `left_off` | text, null | Latest assistant message (verbatim) |
| `pid` | int, null | Agent process id |
| `pid_start` | int, null | Process start time (clock ticks on Linux; `lstart` epoch on macOS) |
| `boot_id` | text, null | Boot id when last seen running |
| `tmux_pane` | text, null | `$TMUX_PANE` at last sight |
| `started_at`, `last_activity_at`, `state_since` | text | |
| `project_id` | text FK Project.id, null | |
| `parked` | int | 0/1 |
| `dismissed` | int | 0/1; hides from default view (FR-019) |
| `done_at` | text, null | Set only by the user (FR-019b). Valid only when `state = finished`. Moves the session into the Done section of its project, or the global Done section if `project_id` is null. Cleared by unmark or by respawn (FR-019c). Not a state: reconcile never touches it. |

Indexes: `(state, last_activity_at)`, `(project_id)`, `(repo_root)`, `(agent_kind, agent_session_id)` unique.

### State machine

States: `working`, `needs_permission`, `idle`, `finished`, `interrupted`, `unknown` (spec FR-002; `needs_permission` is the "waiting for the user" state, and Copilot `elicitation_dialog` maps to it too).

```text
            hook events                       reconcile (pid/boot_id/pane)
SessionStart ─► idle
UserPromptSubmit / Pre/PostToolUse ─► working
PermissionRequest | Notification(permission_prompt|elicitation_dialog) ─► needs_permission
Stop | Notification(idle_prompt|agent_idle|agent_completed) ─► idle
SessionEnd (reason != clear) ─► finished
SessionEnd (reason == clear) ─► finished + new Session(resumed_from = this)
Copilot sessionEnd (reason error|abort|timeout) ─► interrupted (work did not end cleanly)

any non-finished state ──(boot_id differs OR pid gone/start differs OR pane gone)──► interrupted
passive-only discovery ─► unknown (until first hook)
interrupted ──(respawn then matching SessionStart in recorded pane)──► superseded: new Session.resumed_from = this;
                                                                      this stays `interrupted` but hidden behind the head
finished/interrupted ──(user action)──► dismissed/parked flags (state unchanged)
finished ──(respawn; matching SessionStart in recorded pane)──► new Session.resumed_from = this; head of chain is active again
```

View sections (derived, not stored): per scope (global, or one project) the groups are Active (working, needs_permission, idle), Interrupted, Finished (`finished` and `done_at` null), Done (`done_at` not null), and, hidden by default, Dismissed. A session appears in exactly one group; the Done group of a project contains only that project's sessions, and the global scope lists sessions with `project_id` null in its own Done group. `done_at` is cleared when a respawn is requested for the session.

`finished` is never hidden by the system: the only thing that removes a session from the default view is `dismissed = 1`, set by the user. Finished sessions use the same respawn planner and checks as interrupted ones (FR-019a). Only `interrupted` ones are pre-selected by `boot-check`/`restore`.

Rules: a "running" indicator is derived (`state in working|needs_permission|idle` and liveness holds), never stored. `state_since` is kept when the state does not change (existing behaviour). Reboot: reconcile sets every non-finished session whose `boot_id` differs from the current one to `interrupted` in one statement.

### Project  (spec: Project)

| Field | Type | Notes |
|---|---|---|
| `id` | text PK | UUID v4 |
| `name` | text unique | |
| `status` | text | `active` \| `parked` \| `done` \| `archived` |
| `note` | text, null | |
| `progress_binding_id` | text FK, null | Chosen plan source for the project |
| `created_at`, `updated_at` | text | |

Combined state summary is a query (count of sessions by state), not a column.

### Step / Plan item  (spec: Plan / Progress)

Rows are snapshots, replaced wholesale when the source is re-read; a step has no identity beyond `(binding_id, ordinal, text)`.

| Field | Type | Notes |
|---|---|---|
| `binding_id` | text FK ProgressBinding.id | |
| `ordinal` | int | Order in source |
| `text` | text | |
| `status` | text | `todo` \| `doing` \| `done` \| `blocked` |
| `group` | text, null | e.g. spec-kit phase heading |
| `external_id` | text, null | e.g. `T017` |

### ProgressBinding

| Field | Type | Notes |
|---|---|---|
| `id` | text PK | |
| `owner_kind` | text | `session` \| `project` |
| `owner_id` | text | |
| `source_kind` | text | `agent_todo` \| `speckit_tasks` \| `markdown_checklist` |
| `source_path` | text, null | Absolute path for file sources; null for agent todo |
| `chosen_by` | text | `auto` \| `user` (FR-015a) |
| `read_at` | text | Last parse time |

### Note / Marker

`note(id, owner_kind, owner_id, body, created_at, author)`; parked and dismissed are columns on Session/Project (above).

### Summary

`summary(id, owner_kind, owner_id, body, model, model_written int, created_at)`. Verbatim text lives on Session; model-written text is only ever in this table and is labelled in views (FR-017a).

### CortexiphanLink  (spec: Cortexiphan Link)

| Field | Type | Notes |
|---|---|---|
| `id` | text PK | |
| `owner_kind`, `owner_id` | text | Project, step binding or note |
| `cortex_node_id` | text | Cortexiphan `NodeId` (u64 per shard) rendered as text |
| `cortex_doc_id` | text, null | |
| `cortex_kind` | text | `project` \| `task` \| `memory` |
| `last_agreed_at` | text, null | Last time both sides matched |
| `last_remote_status` | text, null | Cached; null when unreachable |

### RespawnRequest  (spec: Respawn Request)

| Field | Type | Notes |
|---|---|---|
| `id` | text PK | |
| `session_id` | text FK | Original |
| `requested_at` | text | |
| `outcome` | text | `started` \| `refused:<code>` \| `failed:<detail>` |
| `tmux_target` | text, null | Window/pane started |
| `new_session_id` | text FK, null | Filled when the matching `SessionStart` arrives |

Refusal codes: `already_running`, `missing_directory`, `missing_transcript`, `branch_gone`, `no_launcher`, `no_tmux`.

### Event  (spec: Attribution)

The `seq` column is also the **change-feed cursor**: viewers, the SSE stream and the cortexiphan export each remember the last `seq` they handled and read only newer rows (research D12). Append-only: `events(seq integer PK, at, entity_kind, entity_id, kind, payload_json, author_kind, author_name)`.

`author_kind`: `user` \| `agent` \| `system`; `author_name`: user name, or agent kind plus model if known (`claude`/`claude-opus-5-5`), or the component (`reconcile`, `hook`). One row per mutation of any entity above (not per hook tick that changes nothing).

## Mappings to cortexiphan (FR-023, FR-024; format in `contracts/cortexiphan-export.md`)

| Control centre | Cortexiphan | Rule |
|---|---|---|
| Project | `Node{kind: Project}` + `ProjectFields` | `status`: active→`Active`, parked→`Paused`, done→`Done`, archived→`Archived` |
| Project repo links (from member sessions) | `ProjectFields.repos: RepoRef{name, uri, clones[{machine, path}]}` | `name` = repo dir name, `uri` = git remote if any, clone = `{hostname, repo_root}` |
| Step | `Node{kind: Task}` + `TaskFields` | `todo→Todo`, `doing→Doing`, `done→Done`, `blocked→Blocked`; `PartOf` edge to the project |
| Note | `Node{kind: Memory}` linked to the project | body verbatim |
| Session | `Node{kind: Custom{kind:"session", fields}}` | fields: agent_kind, agent_session_id, cwd, branch, state, last_activity_at, resumed_from; session conversation text is never exported |
| Event author | `Provenance{author}` | `user`→`User`, `agent`→`Llm{model}`, `system`→`Connector{name:"ai-control-centre"}` |
| Any exported entity id | `ExternalRef{system:"ai-control-centre", id, url:null}` | dedupe key `(system,id)` |

## Validation rules (from the spec)

- `Session.cwd` never rewritten to a different path by respawn; respawn into a different directory is refused, not corrected (FR-012).
- A progress figure is only produced from a `ProgressBinding` with a real source; no binding → no figure (FR-016).
- `summary.model_written = 1` rows are never shown without the label, and never copied into `Session.left_off` (FR-017a).
- `done_at` can be set only on a `finished` session by a user action (event author `user`); setting it on any other state is rejected with an explanatory error.
- Dismissal never deletes rows; deleting a record is a separate explicit command.
- Reconcile is idempotent: running it twice yields the same states.
