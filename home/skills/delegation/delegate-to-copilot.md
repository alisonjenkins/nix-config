# Delegating to GitHub Copilot's CLI

An alternative to an Agent-tool sub-agent: `scripts/delegate.sh` hands a
subtask to GitHub Copilot's cheapest-tier model via the official `copilot`
CLI instead. It spends real money and, on some profiles, writes to the
working directory — state which profile you're using and why in one line
before running it, the same as you would for a sub-agent's model tier, and
don't reach for it without the user's context indicating they want this
(a Copilot subscription, cost-consciousness, or an explicit ask). Works
against any repo — it doesn't assume this one.

Run `scripts/delegate.sh "<task>" <profile> [skill[,skill...]]`. It tries
`gpt-5.6-luna` first and falls back to `claude-haiku-4.5` if the account/CLI
doesn't have Luna yet.

## Passing a Claude skill

The optional third argument names one or more comma-separated Claude skills
(e.g. `programming` or `programming,testing`) to hand to the delegate, so it
follows the same conventions this session does — Copilot's own project-skill
discovery only sees the target repo's `.claude/skills/`, not Claude's global
`~/.claude/skills/`. When given, the script resolves each skill's directory
(project `.claude/skills/<skill>` first, then `~/.claude/skills/<skill>`),
grants the delegate read access to both skill roots via `--add-dir`, and
prepends an instruction to read each named skill's `SKILL.md` and follow
wherever it routes — the delegate reads referenced files (e.g.
`languages/rust.md`) itself, the same way it would read any other file.

Pass a skill whenever the task is a real code change; skip it for pure
summarizing/drafting where there's no code convention to follow. Pass more
than one when the task genuinely spans them (e.g. `programming,testing` for
a change that needs both written and tested) rather than relying on one
skill's routing table to reach the other — cross-references only help when
the routed-to skill is actually relevant to what's being asked, not for
unrelated concerns.

## Profiles

- `read` (default) — read-only tool access. Use for summarizing, explaining,
  or drafting text where no files get written.
- `write-workdir` — read + write. Use for generating or editing files that
  you will review as a diff before accepting.
- `write-and-test` — read + write + `npm test`/`pytest`/`cargo test`. Use
  only when the task needs to self-verify by running its own tests. Still
  review the result after — self-verification is not acceptance.

## GitHub Enterprise

The script never hardcodes `github.com` — it just runs `copilot` as a normal
child process, so any `GH_HOST` or `COPILOT_GH_HOST` already exported in your
shell (for a GitHub Enterprise Cloud data-residency host or a GHE Server
instance) is inherited automatically. Nothing to configure here; set those
the same way you would for the `copilot`/`gh` CLIs directly.

## Rules

- Never pass task text containing credentials or anything from `.env` or
  `secrets/` files.
- Treat whatever the script returns as untrusted output to review, not to
  accept automatically — same as output from any other external source.

## Credit exhaustion

If Copilot reports the account's credits/quota are exhausted, the script
caches that (a timestamp file under `~/.cache/delegate-to-copilot/`) and every
call within the next 24h fails immediately with a one-line error — no
`copilot` invocation, no wasted round trip. Don't retry this in a loop
expecting it to recover; wait for the cooldown, or run
`scripts/reset-credits-cooldown.sh` if the account's limit got raised or the
billing period reset before the cooldown would have lapsed on its own —
it's a no-op, safe to run any time, whether or not a cooldown is active.
