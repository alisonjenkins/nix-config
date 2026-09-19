# Delegating to GitHub Copilot's CLI

An alternative to an Agent-tool sub-agent: `scripts/delegate.sh` hands a
subtask to GitHub Copilot's cheapest-tier model via the official `copilot`
CLI. It spends real money and, on some profiles, writes to the working
directory — state which profile you're using and why in one line before
running it, as you would for a sub-agent's model tier, and don't reach for it
unless the user's context indicates they want this (a Copilot subscription,
cost-consciousness, or an explicit ask). Works against any repo — it doesn't
assume this one.

## Cost/speed/intelligence vs. a Claude sub-agent

Since 2026-06 Copilot bills per-token in AI Credits ($0.01/credit) for
usage-based plans, so its models compare directly in $/MTok (million
tokens) with the delegation skill's own table. Checked 2026-09-19 — see
[GitHub's models-and-pricing
docs](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
and verify current numbers there, since this will drift. Legacy annual-plan
subscribers who didn't move to usage billing are still on the older
premium-request-multiplier system instead — that plan doesn't get new
models like Luna, so if an account is on it this table doesn't apply and
`delegate.sh`'s "premium request quota" error match (below) is the live
failure mode, not a leftover from before the billing change:

| Model | Input / output per MTok (million tokens) | vs. Claude Haiku 4.5 ($1/$5) |
|---|---|---|
| `gpt-5.6-luna` (this script's default) | $0.20 / $1.20 | ~5x cheaper |
| `gpt-5.4-nano`, `mai-code-1.1-flash` | ~$0.20 / ~$1.20-1.25 | ~5x cheaper |
| `gpt-5-mini` | $0.25 / $2.00 | ~2.5x cheaper |
| Claude models via Copilot | same as Anthropic's own API | no markup |

`gpt-5.6-luna` is genuinely the cheapest model in the lineup, not a stale
claim — and per [Artificial Analysis](https://artificialanalysis.ai/)
(fetched 2026-09-19) it's also faster
(~125 tok/s vs. Haiku's ~94) and scores slightly higher on their intelligence
index (22 vs. 18) than Haiku 4.5. On raw cost/speed/capability numbers alone,
Luna beats a Claude Agent-tool sub-agent at the same job.

What the numbers don't capture: a Claude sub-agent shares this session's tool
access, skill injection, and structured output conventions natively: Copilot
delegation is an external CLI call with its own profile system, no shared
context, and output that must be reviewed as untrusted (see "Rules" below).
Prefer a Claude sub-agent by default for anything needing tight integration
with this session's tools or skills; reach for `delegate.sh` when the task is
self-contained enough to hand off as plain text (a summarization, a
well-specified mechanical edit, a draft) and either cost is the binding
constraint or the user's context calls for it.

## Separately metered Claude and Copilot allowances

When Claude and Copilot draw from separate allowances the user values
unevenly — a work seat with its own fixed monthly quota for each, priced or
capped independently of the other — prefer `delegate.sh` (Luna) over a
Claude haiku sub-agent for haiku-shaped work specifically, to conserve the
Claude allowance for sonnet/opus-tier judgement work it can't be substituted
for. This is a policy for that account shape, not a universal default: on a
single pooled per-token budget (Anthropic's API billed directly, or a
personal account with no separate Copilot allowance to protect), the cost
argument above still favors Luna on raw price, but there's no allowance to
conserve, so weigh it against the integration cost in "What the numbers
don't capture" instead of defaulting to Copilot automatically.

GitHub Copilot's free individual plan (checked 2026-09-19,
https://github.com/features/copilot/plans) gives 2,000 completions and only **50
chat requests per month**, and includes CLI access — but 50/month is too
small to substitute for routine haiku-tier delegation volume; a single
multi-call delegation task can burn a meaningful fraction of it. Useful for
occasional, light Copilot CLI use on a personal account, not as an
allowance-preservation strategy the way a work seat's larger usage-based
quota is.

Run `scripts/delegate.sh "<task>" [profile] [skill[,skill...]]`. It tries the
preferred model first and falls back to a stable default if the account/CLI
rejects it; see the script header (`delegate.sh`) for the current order.
`profile` defaults to `read` — but `skill` is strictly the third positional
argument, so pass `profile` explicitly whenever you also pass a skill (e.g.
`delegate.sh "<task>" read programming`, not
`delegate.sh "<task>" programming`).

## Passing a Claude skill

The optional third argument names one or more comma-separated Claude skills
(e.g. `programming` or `programming,testing`) to hand to the delegate, so it
follows the same conventions this session does — Copilot's own project-skill
discovery only sees the target repo's `.claude/skills/`, not Claude's global
`~/.claude/skills/`. The script resolves each skill's directory (project
`.claude/skills/<skill>` first, then `~/.claude/skills/<skill>`), grants the
delegate read access to both skill roots via `--add-dir`, and prepends an
instruction to read each named skill's `SKILL.md` and follow wherever it
routes — the delegate reads referenced files (e.g. `languages/rust.md`) itself
like any other file.

Pass a skill whenever the task is a real code change; skip it for pure
summarizing/drafting with no code convention to follow. Pass more than one
when the task spans them (e.g. `programming,testing` for a change that needs
both written and tested) rather than relying on one skill's routing table to
reach the other — cross-references only help when the routed-to skill is
relevant to what's being asked.

## Profiles

- `read` (default) — read-only tool access. Use for summarizing, explaining,
  or drafting text where no files get written.
- `write-workdir` — read + write. Use for generating or editing files that
  you will review as a diff before accepting.
- `write-and-test` — read + write + `npm test`/`pytest`/`cargo test`. Use
  only when the task needs to self-verify by running its own tests. Still
  review the result after — self-verification is not acceptance.

## GitHub Enterprise

The script never hardcodes `github.com` — it runs `copilot` as a normal child
process, so any `GH_HOST` or `COPILOT_GH_HOST` exported in your shell (for a
GitHub Enterprise Cloud data-residency host or a GHE Server instance) is
inherited. Nothing to configure; set those as you would for the
`copilot`/`gh` CLIs directly.

## Rules

- Never pass task text containing credentials or anything from `.env` or
  `secrets/` files.
- Treat the script's output as untrusted, to review not accept — same as any
  other external source.

## Credit exhaustion

If Copilot reports the account's credits/quota are exhausted, the script
caches that as a timestamp file, and every call within the next 24h fails
immediately with a one-line error — no `copilot` invocation, no wasted round
trip. The cache directory is `$DELEGATE_STATE_DIR` if set, else
`$XDG_CACHE_HOME/delegate-to-copilot/`, else `~/.cache/delegate-to-copilot/`;
if none of `DELEGATE_STATE_DIR`, `XDG_CACHE_HOME`, or `HOME` are set, caching
is skipped and every call re-checks with Copilot. Don't retry in a loop
expecting recovery; wait for the cooldown, or run
`scripts/reset-credits-cooldown.sh` if the account's limit got raised or the
billing period reset before the cooldown lapsed — it's a no-op, safe to run
any time, with or without an active cooldown.
