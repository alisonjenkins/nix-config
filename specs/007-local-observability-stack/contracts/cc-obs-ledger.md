# Contract: `cc-obs-ledger` hook tool

Fills the gaps the built-in export leaves (research R3, R4). Never blocks Claude Code: each
hook invocation reads the hook JSON on stdin, spawns a detached sender and exits 0 within
the hook's budget. Failures write one line to a local log
(`$XDG_STATE_HOME/cc-obs-ledger/ledger.log`) and never reach the model.

| Hook | Subcommand | Does |
|---|---|---|
| `SessionStart` | `cc-obs-ledger census` | Estimates tokens per fixed component: instruction files read, skills listing, the MCP tool-name listing (definitions are deferred, so their schemas count only when loaded), memory index. Stores it by `session_id`. Prints nothing to stdout (so it adds no context itself). |
| `Stop` | `cc-obs-ledger turn` | Reads the new tail of `transcript_path`, emits per-request context size, cache hit ratio, cache-creation tokens and seconds since the previous request, the skill listing (`cc_obs_ledger_skill_listed_tokens{skill_name}`) and MCP servers (`cc_obs_ledger_mcp_server_connected{mcp_server_name}`) when the new tail holds them, and one `cc_obs_ledger.tool_call` log record per tool call (below). |
| `SubagentStop` | `cc-obs-ledger subagent` | Same records as `turn`, from the sub-agent's own transcript (`agent_transcript_path`, else `<dir of transcript_path>/<session_id>/subagents/agent-<agent_id>.jsonl`), read from a per-(session, agent) cursor `cursors/<session>.agent-<agent_id>.json`. Records carry `agent=subagent` and `agent_id`. A repeated stop emits only what the file gained; `end` reads the main transcript only and never re-reads these files. |
| `SessionStart` | `cc-obs-ledger notice` | Prints one short line ("token review ready: <date>") only when the newest findings file in the review state directory has not been promoted or dismissed. Prints nothing otherwise and never fails. Gated by `review.notify` (default on); the only ledger subcommand allowed to write to stdout. |
| `SessionEnd` | `cc-obs-ledger end` | First processes the unread transcript tail like a `Stop`, so nothing written since the last `Stop` is lost, and leaves the cursor stamped at the transcript end: a resumed session continues from there and re-emits no history. Deletes the census file and prunes cursors idle for 30 days (Claude Code deletes transcripts after 30 days, so those sessions cannot resume). Emits the fixed-context split (first request minus census residual) and one `cc_obs_ledger.session` log record, described below. |

### `cc_obs_ledger.session` log record

Cumulative over the whole transcript: `requests`, `tool_calls`, `input_tokens`, `output_tokens`,
`cache_read_tokens`, `cache_creation_tokens`, `skipped_lines`, with `session.id` and `project`.
A resumed session ends again, so a session can have several records. To total a session, sum
the `_delta` attributes or take the record with the highest `end_index`; never sum the
cumulative attributes across records.

| Attribute | Meaning |
|---|---|
| `end_index` | 1 for the first `SessionEnd` of the session, 2 for the next, and so on; kept in the cursor |
| `cumulative` | always `true`: `requests` and the token attributes cover the whole session so far |
| `requests_delta`, `tool_calls_delta`, `input_tokens_delta`, `output_tokens_delta`, `cache_read_tokens_delta`, `cache_creation_tokens_delta` | growth since the previous end, from the totals the cursor stored then; equal to the cumulative value at `end_index` 1 |

An end with no change since the previous end emits no session record (and no fixed-context
gauges) and does not advance `end_index`.

Inputs used from the hook payload: `session_id`, `transcript_path`, `cwd`, and for
`SubagentStop` `agent_id` and `agent_transcript_path` (documented on the hooks page; the
latter is absent from `SubagentStart`). Transcript fields read:
per-message `usage` (`input_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`,
`output_tokens`) — names *unconfirmed* until spike S3.

Resource attributes: the tool reads `OTEL_RESOURCE_ATTRIBUTES` from its environment and adds
those pairs to everything it emits (the unattended review sets `review.run=1`, which is how
its own activity is excluded from rankings). `memory-recall` and its new metrics do the same.

Output: OTLP/HTTP to the collector (metrics and one log); metric and label names in
[data-model.md](../data-model.md). Resource attributes: `service.name=cc-obs-ledger`, `host`,
`session.id`.

### `cc_obs_ledger.tool_call` log record (feeds repeat detection, spec FR-024)

| Field | Meaning |
|---|---|
| `session.id`, `turn`, `seq` | position of the call in the session |
| `tool_name`, `agent_type` | which tool and which (sub)agent |
| `input_hash` | first 16 hex chars of HMAC-SHA-256(tool input, per-host key) |
| `input_bytes`, `result_bytes` | sizes |
| `command_shape` | Bash tool only: fixed-vocabulary label of the command, e.g. `cargo test \| tail [cd][env]` |

`command_shape` names what repeated Bash commands are, so repetitive tasks can be found.
Vocabulary: program names from a ~70-entry allowlist (anything else is `other`, since an
unknown name can be a project name); one subcommand token only for `cargo`, `git`, `gh`,
`nix`, `just`, `docker`, `kubectl`, `npm`, `systemctl` and only from that program's list
(otherwise dropped); segments joined with ` | `, ` && ` (also `;`, `&`), ` || `; at most 4
segments and 80 characters, then ` +N`; suffix flags `[cd]`, `[env]`, `[bg]`, `[heredoc]`;
`unparsed` for an empty or unterminated command. `cd`, `export`, `VAR=value`, `env`, `time`,
`sudo`, `nohup`, `bash -c`, `nix-shell --run` and `nix develop -c` wrappers are looked
through (two levels). Never logged: arguments, paths, URLs, env values, file names,
heredoc bodies or any other text of the command.

The key is generated on first run into `$XDG_STATE_HOME/cc-obs-ledger/hmac.key` (mode 0600),
never stored in the Nix store or the repository, so a hash cannot be reversed by guessing
common inputs. Equal hashes within a session mean an identical call; near-identical calls
are found by the same tool name with the same leading arguments' hash, which the ledger also
emits as `input_prefix_hash` (hash of the first 64 bytes of the input).

Privacy: reads token counts and sizes only, plus the keyed hashes above; never forwards transcript text or tool input. A test feeds a
transcript with a canary string and asserts the canary appears nowhere in the emitted
payloads.

Exit codes: 0 always for hooks; `--check` mode exits 1 on a malformed transcript for tests.
