# Contract: hook payloads to events

`claude-monitor hook --agent <kind>` reads one JSON object on stdin. Unknown fields are ignored; a missing `session_id`/`sessionId` or event name is a silent no-op (existing behaviour). Fields marked (R2) or (R3) are to be confirmed against recorded fixtures by the spikes in `research.md`; the parser is written against the fixture, not this table.

## Claude Code (`--agent claude`, the default)

Registered by the Home Manager module in `programs.claude-code.settings.hooks` (as today), plus `PostToolUse` already matches `*` and now also feeds the todo list.

| Payload event (`hook_event_name`) | Fields used | Effect |
|---|---|---|
| `SessionStart` | `session_id`, `cwd`, `source` (R2: `startup\|resume\|clear\|compact`) | create/refresh Session; capture pid, pid_start, boot_id, `$TMUX_PANE`; state `idle`. `source=resume` from a pane in an open RespawnRequest sets `resumed_from`. |
| `UserPromptSubmit` | `prompt` | state `working`; set `task_description` if empty |
| `PreToolUse`, `PostToolUse` | `tool_name`, `tool_input` | state `working`; if the todo tool (R2: name and shape), replace the session's agent-todo snapshot |
| `PermissionRequest` | | state `needs_permission` |
| `Notification` | `notification_type` | `permission_prompt` → `needs_permission`; `idle_prompt` → `idle`; others ignored |
| `Stop` | `transcript_path`, last assistant message if present (R2) | state `idle`; update `left_off` (payload, else tail of the transcript) |
| `SessionEnd` | `reason` (R2) | `finished`, raw reason stored; `reason=clear` also opens a lineage step |

Every hook also refreshes `last_activity_at`, `branch` (from `cwd`), and, if changed, `tmux_pane`. Pid capture uses the hook process's parent; if the parent is a shell wrapper the recorded pid is the wrapper, which still dies with the agent (R2/R3 verify on both agents).

## Copilot CLI (`--agent copilot`)

Registered by a hooks file the module writes to `~/.copilot/hooks/claude-monitor.json` (or `$COPILOT_HOME/hooks/`), `version: 1`, one handler per event running `claude-monitor hook --agent copilot`. Payloads are camelCase (a snake_case variant with `hook_event_name` exists; the parser accepts both).

| Event | Fields | Effect |
|---|---|---|
| `sessionStart` | `sessionId`, `cwd`, `source` (`startup\|resume\|new`), `initialPrompt?` | create/refresh; state `idle`; capture pid (R3), boot_id, pane |
| `userPromptSubmitted` | `prompt` | `working`; set `task_description` if empty |
| `preToolUse`, `postToolUse`, `postToolUseFailure` | `toolName`, `toolArgs` | `working` |
| `permissionRequest` | schema undocumented (R3) | `needs_permission` |
| `notification` | `notification_type`: `permission_prompt`, `elicitation_dialog` | `needs_permission` |
| `notification` | `agent_idle`, `agent_completed` | `idle` |
| `agentStop` | `transcriptPath`, `stopReason` | `idle`; update `left_off` from the transcript tail |
| `sessionEnd` | `reason`: `complete\|error\|abort\|timeout\|user_exit` | `finished` (`error`/`abort`/`timeout` stored raw; treated as `interrupted` rather than `finished`, because the work did not complete cleanly) |

### Passive discovery (no hooks required)

`~/.copilot/session-state/*/workspace.yaml` → `agent_session_id=id`, `cwd`, `repo_root=git_root`, `branch`, `started_at=created_at`, `last_activity_at=updated_at`, name; first `user.message` in `events.jsonl` → `task_description`. A discovered session with no hook history has `state=unknown`. Discovery runs inside `reconcile`, reads these files read-only, and never imports assistant or tool content beyond the first prompt.

## Failure behaviour (both)

- Exit 0, empty stdout, always.
- On any error (DB locked beyond `busy_timeout`, bad JSON, I/O): append one line to `<state-dir>/hook.log` with timestamp (UTC), agent, event and error; drop the update. The next hook or reconcile repairs state; reconcile derives liveness without hooks, so a lost hook never produces a wrong "running".
- Total time budget: < 50 ms p95 target; `busy_timeout` ≤ 200 ms inside hooks (viewers use longer).
