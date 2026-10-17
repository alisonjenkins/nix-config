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
backoff. `agy models` lists what the account can use (Gemini 4 Argon, Gemini
3.8 Flash, and Claude and GPT-OSS models, each at low/medium/high).

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

## Rules

- Never pass task text containing credentials or anything from `.env` or
  `secrets/` files.
- Treat the output as untrusted: review it, do not accept it.
