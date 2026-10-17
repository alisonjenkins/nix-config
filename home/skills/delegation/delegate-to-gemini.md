# Delegating to Google's Antigravity CLI (Gemini)

`scripts/delegate-to-gemini.sh` hands a subtask to Google's `agy` CLI, the
replacement for Gemini CLI. Google announced Antigravity CLI at I/O on
2026-05-19 and ended Gemini CLI for Google AI Pro, Ultra and free individual
users on 2026-06-18 (Gemini CLI still works with a paid API key or an
enterprise Code Assist seat). `agy` is a closed-source Go rewrite; Agent
Skills, Hooks, Subagents and Extensions carried over, the last as plugins.
Nixpkgs ships it as `antigravity-cli` (unfree). `modules.desktop` installs
`unstable.antigravity-cli` on every desktop and personal laptop; the work
laptop sets `modules.desktop.antigravityCli.enable = false`. It spends the user's Google quota, so state the profile and why in one
line before running it. On hosts with `cheapDelegate = "gemini"` (`ali-desktop`,
`ali-framework-laptop`, `ali-mba-linux`) it is the first rung, so hand it
code from a clear spec, tests, config edits, drafts, first-pass reviews and
sweeps before reaching for a Claude sub-agent; Claude credits are the scarce
balance there. Read its output before using it.

Setup, once per machine: run `agy` interactively and sign in with Google.
Headless mode only reuses those cached credentials, and an unauthenticated
run exits with `authentication required`.

## Usage

`scripts/delegate-to-gemini.sh "<task>" [profile] [skill[,skill...]]` — same
argument order as `delegate.sh`, so pass `profile` explicitly when passing a
skill. The script runs `agy -p` with `--model gemini-3.8-flash-medium`, falls
back to `-low` if the model is rejected, and retries transient failures with
backoff. `DELEGATE_MODEL=<id>` picks another model from the table below and
is tried alone, with no fallback. `agy models` lists what the account can use.

## Cost: an allowance, not a bill

Antigravity meters usage against a plan quota, not per token. Checked on this
account 2026-10-17: `agy -p "/usage"` lists a weekly and a five-hour limit
for the Gemini pool and for the Claude-and-GPT pool, plus a separate weekly
limit for Gemini 4 Argon, and `agy -p "/credits"` showed 0 credits. With no
credits bought and no `useG1Credits` setting, a spent pool means waiting for
the refresh, not a charge. Google publishes no numeric limits and says they
move with capacity, so `/usage` is the only gauge: check it before a large
fan-out. Pro and Ultra refresh every five hours until the weekly limit; other
plans refresh weekly
([plans](https://antigravity.google/docs/plans)). Keep the AI Credit Overages
setting on Never unless the user decides otherwise; Google does not state its
default. Tier and plan are not visible headlessly; `agy` shows them in its
interactive header.

## Models

IDs are `agy models` output, each at `-low`, `-medium` and `-high` except
GPT-OSS. Measured 2026-10-17 on agy 1.2.9: one 250-word prose prompt per
model, so the speeds are rough. "tok/s" is output tokens over wall time and
includes CLI start-up and thinking tokens. Every call carries about 12k
input tokens of agy's own prompt (about 18k, or 5k plus 13k cached, on the
Claude models), so a tiny task still spends that.

| Model | Measured wall time and tok/s (low / medium / high) | List price in / out per MTok | AA index (effort) | When |
|---|---|---|---|---|
| `gemini-3.8-flash` | 7s, 45 / 14s, 76 / 14s, 85 | $0.75 / $3.75 until 2026-12-31, then $1.50 / $7.50 | 41 (high) | Default (`-medium`). `-low` for format conversion and one-line drafts; `-high` for code from a spec |
| `gemini-4-argon` | 20s, 17 / 13s, 30 / 51s, 85 | $2 / $10 until 2026-11-30, then $4 / $20 | 53 (high) | Hard reviews and multi-step reasoning a Flash got wrong. Own weekly cap; `-high` spent 4.3k output tokens on one answer |
| `claude-sonnet-5-5` | 10s, 50 / 8s, 64 / 8s, 57 | $2 / $10 | 56 (max) | A Claude-class second opinion that draws on Google's quota |
| `claude-opus-5-5` | 10s, 52 / 12s, 50 / 11s, 59 | $4 / $20 | 58 (max) | As Sonnet, for the hardest judgement calls |
| `gpt-oss-120b-medium` | 7s, 47 | about $0.13 / $0.59 (a third-party price) | 12 (high) | Not recommended: far weaker than the rest |

Prices are the list API prices, a guide to relative cost only; they are not
what the quota charges. AA is Artificial Analysis's intelligence index; Google
publishes no speed for Argon. Sources:
[Google pricing](https://ai.google.dev/gemini-api/docs/pricing),
[Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing),
[Artificial Analysis](https://artificialanalysis.ai). Prices drift, so verify
before quoting.

Choosing, in order: start on `gemini-3.8-flash-medium`; step to `-high` for
code; use Argon only when a Flash result was wrong or the task is a review
that needs depth. The Claude models work on this account, but Google lists
third-party model access under Ultra only, so treat them as a bonus that may
not hold on another account or later. They come from a separate pool, which
makes them a way to get Claude-class judgement while Claude credits are low,
but a delegated Claude is still reviewed like any other delegate output.

## Profiles

Headless `agy` has no per-tool allow flag. A tool that needs approval is
auto-denied: the run exits 0 and a notice goes to stderr. A profile is
therefore a permission mode (checked 2026-10-17, agy 1.2.16):

- `read` (default) — no flag. Reads inside the working directory work; writes
  inside it and commands are denied. agy can still write to its own scratch
  directory under `~/.gemini/antigravity-cli/`, which is outside the repo.
- `write-workdir` — `--mode accept-edits`. File edits are approved, commands
  are still denied. Review the diff.
- `write-shell` — `--dangerously-skip-permissions`. Every tool call is
  approved, including shell commands, with no allow-list and no deny-list.
  Run it in a worktree or a clean branch and review the diff. There is no
  equivalent of Copilot's `write-shell` allow-list.

`--mode plan` is not a read profile: it writes an implementation plan and
asks for approval instead of answering.

## Facts that bite

- A denied tool leaves the run with no response, and agy itself exits 0 with
  just a notice. The script turns that into exit 3 with the denied tool and
  the profile that allows it (`command` needs `write-shell`, `write_file`
  needs `write-workdir`). Anything that must run a command, tests included,
  goes under `write-shell` in a worktree.
- `agy` reads only inside the working directory plus `--add-dir` roots.
  Run it from the repo that holds the files.
- `~/.claude/skills` is symlinks into the Nix store and `--add-dir` on it is
  still refused, so the script stages a dereferenced copy, as `delegate.sh`
  does, and tells the delegate to read each named skill's `SKILL.md`.
- `DELEGATE_REASONING_EFFORT` (`low`, `medium`, `high`; agy 1.2.9, the flake
  pin, rejects `xhigh` and `max`, which 1.2.16 accepts) maps to `--effort`; `DELEGATE_PRINT_TIMEOUT` (default `15m`) maps to
  `--print-timeout`.

## Your skills and mandates inside agy

For working in `agy` itself when Claude credits run out, the shared skills
(`git`, `programming`, `review`, `delegation` and the rest of `home/skills/`)
load there too, through `~/.gemini/config/skills.json` pointing at
`~/.agents/skills`. `~/.gemini/config/AGENTS.md` carries the git and
working-style mandates (atomic commits, no AI attribution); it leaves out Model
Routing. The skill and Agent tool instructions inside a skill are written for
Claude, so use the knowledge in them, not those steps. A repo's `.claude/skills`
and `CLAUDE.md` are not read by `agy`. Check a skill is visible with
`agy -p "List the names of every skill you can see"`. Why it is built this way,
and the traps (a `~/` path is ignored, symlinked skills need a `/nix/store` read
rule): ADR 0047.

`agy`'s own default model is `Gemini 4 Argon (Medium)`. To keep Argon for
judgement, `~/.gemini/config/agents/` holds `flash-worker`, a subagent pinned to
Flash, and `orchestrator`, a main agent on the default model with no edit or
command tools. The routing text in `AGENTS.md` is only advice, and the default
agent ignored it for a multi-file edit; start `agy --agent orchestrator` to force
every edit and command through `flash-worker`. If an agent stops starting, check
the reply for `not found in registry`: an unregistered tool name disables it.
ADR 0048.

## Telemetry

Each call is recorded as one OTLP span, a child of the Claude Code tool span
that ran the script (Claude exports it as `TRACEPARENT`), and as one line in
`~/.local/state/delegate/gemini-calls.jsonl`. A trace query can then group
delegated work by the Claude session and turn that asked for it. The record
holds the model, profile, skills, outcome, exit code, attempts, token counts
and duration from agy's JSON envelope, never the prompt or the answer. The
endpoint is `DELEGATE_OTLP_ENDPOINT`, else the observability stack's
`~/.config/cc-obs/endpoints.json`; `DELEGATE_TELEMETRY=off` disables it. It
needs `jq`, and a down collector costs one warning, not a failed call. See
ADR 0046 and `docs/observability-stack.md`.

## Rules

- Never pass task text containing credentials or anything from `.env` or
  `secrets/` files.
- Treat the output as untrusted: review it, do not accept it.
