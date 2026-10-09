# Contract: `cc-obs-ledger` hook tool

Fills the gaps the built-in export leaves (research R3, R4). Never blocks Claude Code: each
hook invocation reads the hook JSON on stdin, spawns a detached sender and exits 0 within
the hook's budget. Failures write one line to a local log
(`$XDG_STATE_HOME/cc-obs-ledger/ledger.log`) and never reach the model.

| Hook | Subcommand | Does |
|---|---|---|
| `SessionStart` | `cc-obs-ledger census` | Estimates tokens per fixed component: instruction files read, skills listing, the MCP tool-name listing (definitions are deferred, so their schemas count only when loaded), memory index. Stores it by `session_id`. Prints nothing to stdout (so it adds no context itself). |
| `Stop` | `cc-obs-ledger turn` | Reads the new tail of `transcript_path`, emits per-request context size and cache hit ratio, and one `cc_obs_ledger.tool_call` log record per tool call (below). |
| `SessionStart` | `cc-obs-ledger notice` | Prints one short line ("token review ready: <date>") only when the newest findings file in the review state directory has not been promoted or dismissed. Prints nothing otherwise and never fails. Gated by `review.notify` (default on); the only ledger subcommand allowed to write to stdout. |
| `SessionEnd` | `cc-obs-ledger end` | Emits the fixed-context split (first request minus census residual) and one `cc_obs_ledger.session` log line. |

Inputs used from the hook payload: `session_id`, `transcript_path`, `cwd`, `agent_id` /
`agent_type` when present (common fields, per the hooks docs). Transcript fields read:
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

The key is generated on first run into `$XDG_STATE_HOME/cc-obs-ledger/hmac.key` (mode 0600),
never stored in the Nix store or the repository, so a hash cannot be reversed by guessing
common inputs. Equal hashes within a session mean an identical call; near-identical calls
are found by the same tool name with the same leading arguments' hash, which the ledger also
emits as `input_prefix_hash` (hash of the first 64 bytes of the input).

Privacy: reads token counts and sizes only, plus the keyed hashes above; never forwards transcript text or tool input. A test feeds a
transcript with a canary string and asserts the canary appears nowhere in the emitted
payloads.

Exit codes: 0 always for hooks; `--check` mode exits 1 on a malformed transcript for tests.
