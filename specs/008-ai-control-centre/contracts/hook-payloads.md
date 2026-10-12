# Contract: hook payloads to events

`claude-monitor hook --agent <kind>` reads one JSON object on stdin. Unknown fields are ignored; a missing `session_id`/`sessionId` or event name is a silent no-op (existing behaviour). Claude fields were confirmed on Claude Code 2.1.293 by spike R2 (2026-10-12); redacted fixtures are in the claude-monitor repo under `tests/fixtures/claude/`. Fields marked (R3) are still to be confirmed against recorded Copilot fixtures. The parser is written against the fixture, not this table.

Present on every Claude payload: `session_id`, `transcript_path`, `cwd`, `hook_event_name`. `prompt_id` is on every event except `SessionStart`. `permission_mode` and `effort{level}` are on `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest` and `Stop`, and absent on `SessionStart`, `SessionEnd` and `Notification` (in `-p` mode `permission_mode` is `"auto"` unless set). `scratchpad_dir` appears in interactive payloads only.

## Claude Code (`--agent claude`, the default)

Registered by the Home Manager module in `programs.claude-code.settings.hooks` (as today), plus `PostToolUse` already matches `*` and now also feeds the todo list.

| Payload event (`hook_event_name`) | Fields used | Effect |
|---|---|---|
| `SessionStart` | `session_id`, `cwd`, `source`: `startup`, `resume` (same `session_id`) or `clear` (new `session_id`); `compact` not tried | create/refresh Session; capture pid, pid_start, boot_id, `$TMUX_PANE`; state `idle`. `source=resume` with a known `session_id` revives that record in place (no new row, no link). `source=clear` creates the new session with `resumed_from` set to the one that just ended in the same pane. |
| `UserPromptSubmit` | `prompt` (full text) | state `working`; set `task_description` if empty |
| `PreToolUse` | `tool_name`, `tool_input`, `tool_use_id` | state `working`. Ignore `tool_name=ToolSearch` (it fires too and is not work). |
| `PostToolUse` | as `PreToolUse` plus `tool_response` (tool specific) and `duration_ms` | state `working`; same `ToolSearch` filter. Todo tool: unverified, see below. |
| `PermissionRequest` | `tool_name`, `tool_input`, `permission_suggestions[]` (e.g. `{type:addDirectories,...}`, `{type:setMode,mode:acceptEdits,...}`). No `tool_use_id`. | state `needs_permission`. Fires in `-p` mode too. |
| `Notification` | `notification_type`, `message`. Interactive sessions only; none in `-p`. | `permission_prompt` (message "Claude needs your permission", right after `PermissionRequest`) → `needs_permission`; `idle_prompt` (message "Claude is waiting for your input", about 60-75 s after `Stop`) → `idle`; others ignored |
| `Stop` | `last_assistant_message` (full text), `stop_hook_active`, `background_tasks[]`, `session_crons[]`, `transcript_path` | state `idle`; update `left_off` from `last_assistant_message` (once per turn, so no transcript read; tail of the transcript only if the field is missing) |
| `SessionEnd` | `reason`: seen `other` (`-p` exit), `clear` (`/clear`, old `session_id`), `prompt_input_exit` (Ctrl-D at an empty prompt, two presses). Not seen: `logout`, `bypass_permissions_disabled`, `resume`. | `finished`, raw reason stored; `reason=clear` is followed by a `SessionStart` with `source=clear` and a new id, which carries the lineage link |

Todo tool row, unverified: the Claude Code used in the spike (2.1.293) has no todo tool (no `TodoWrite`, `TaskCreate` or `TaskUpdate`; its tool list has `Task` (subagents), `TaskStop`, `Cron*`, `Workflow`), so the `tool_input.todos[]` shape could not be captured and it may be gated by a setting. Implement the parser as optional; the absence of the source is normal.

Event order: `-p` run is `SessionStart(startup)`, `UserPromptSubmit`, `[PreToolUse, PostToolUse]*`, `Stop`, `SessionEnd(other)`. A permission prompt is `PreToolUse`, `PermissionRequest`, then `Notification` (interactive only). `/clear` is `SessionEnd(clear, old id)` then `SessionStart(clear, new id)`.

Every hook also refreshes `last_activity_at`, `branch` (from `cwd`), and, if changed, `tmux_pane`. Pid capture uses the hook process's parent (`$PPID`), which is the agent process itself. Its command name is `.claude-wrapped`, so `pgrep -x claude` misses it: take the hook's `$PPID` rather than searching by name. It was stable across `Stop` and `SessionEnd` of a `-p` session; whether it stays the same after an interactive `/clear` is unverified. If the parent turns out to be a shell wrapper the recorded pid is the wrapper, which still dies with the agent (R3 verifies this for Copilot).

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
