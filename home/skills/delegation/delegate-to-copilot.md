# Delegating to GitHub Copilot's CLI

An alternative to an Agent-tool sub-agent: `scripts/delegate.sh` hands a
subtask to GitHub Copilot's cheapest-tier model via the official `copilot`
CLI. It spends real money and, on some profiles, writes to the working
directory — state which profile you're using and why in one line before
running it, as you would for a sub-agent's model tier. It is the default
first rung on machines whose Model Routing mandate names it (nix
`cheapDelegate = "copilot"`, the work laptop); elsewhere, use it only when
the user asks. Works against any repo — it doesn't assume this one.

## Cost/speed/intelligence vs. a Claude sub-agent

Since 2026-06 Copilot bills per-token in AI Credits ($0.01/credit) for
usage-based plans, so its models compare directly in $/MTok (million
tokens) with the delegation skill's own table. Checked 2026-09-28 — see
[GitHub's models-and-pricing
docs](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing)
and verify current numbers there, since this will drift. Legacy annual-plan
subscribers who didn't move to usage billing are still on the older
premium-request-multiplier system instead — that plan doesn't get new
models like Luna, so if an account is on it this table doesn't apply and
`delegate.sh`'s "premium request quota" error match (below) is the live
failure mode, not a leftover from before the billing change:

| Model | Released | Input / output per MTok (million tokens) | vs. Claude Haiku 5.5 ($0.10/$0.50) | AA intelligence index | Output tok/s |
|---|---|---|---|---|---|
| `claude-haiku-5.5` (this script's first choice; ID derived, unconfirmed) | 2026-10-07 | $0.10 / $0.50 | 1x | 43 (max effort) | ~243 |
| GPT-6 Luna (`gpt-6-luna`, this script's second choice) | 2026-09-22 | $0.10 / $0.50 | same price | 38 (max effort) | ~128 |
| `gpt-5.6-luna` (this script's third choice) | 2026-07-09 | $0.20 / $1.20 | ~2x dearer | 37 (max effort) | ~128 |
| `gpt-5.4-nano`, `mai-code-1.1-flash` | — | ~$0.20 / ~$1.20-1.25 | ~2x dearer | — | — |
| `gpt-5-mini` | — | $0.25 / $2.00 | ~2.5-4x dearer | — | — |
| GPT-6 Sol | 2026-09-22 | $2.00 / $10.00 | ~20x dearer | not yet published | not yet published |
| `gpt-5.6-terra` | 2026-07-09 | $2.00 / $12.00 | ~20x dearer | 34 (high) | ~95 |
| GPT-6 Astra (preview) | 2026-09-03 | $10.00 / $50.00 | same as Fable 5.1 | not yet published | not yet published |
| Claude models via Copilot | — | same as Anthropic's own API | no markup | — | — |

Copilot charges the same as OpenAI's own API for all of these. OpenAI's
long-context rates are higher: GPT-6 Luna $0.20 / $0.75 past 272K input
tokens, GPT-5.6 Luna $0.40 / $1.80 past 200K. For comparison, Artificial
Analysis puts Haiku 5.5 at index 34 (medium effort; ~243 tok/s at max),
Haiku 4.5 (legacy) at 15 and ~80 tok/s, Sonnet 5 at 28, and Opus 5.5 at 51. The index moves with effort settings, so read these as rough
gaps.

GPT-6 Luna is the cheapest GPT model in the lineup (Haiku 5.5 ties it), at half GPT-5.6 Luna's
price. `gpt-6-luna` was confirmed against the CLI on 2026-10-06 (copilot
1.0.88): an unknown ID is rejected with "is not available", this one runs.

Claude Haiku 5.5 is also in Copilot (GA 2026-10-07, all paid plans, CLI
included, same $0.10 / $0.50 as Luna; Business and Enterprise admins can
disable it through the model policy). Its CLI ID is `claude-haiku-5.5`,
derived rather than seen: the Copilot CLI changelog's literal IDs are
`claude-opus-5.5` and `claude-fable-5.1`, so Claude IDs are lowercase with a
dotted version and no date suffix. It is unconfirmed on a real account, and
may need a newer CLI than 1.0.88 (v1.0.93 added the 5.5 models to the model
picker). `delegate.sh` therefore tries `claude-haiku-5.5`, then `gpt-6-luna`,
then `gpt-5.6-luna`, then `claude-haiku-4.5`, moving down a step only when the
CLI rejects the model ID, so a wrong ID, an old CLI or a policy block costs
one rejected call, not the task. Check the real list with the `/model` picker.

How they compare (Artificial Analysis, max effort, 2026-10-08): Haiku 5.5
scores 43 at ~243 tok/s; GPT-6 Luna scores 38 at ~128 tok/s. Haiku used about
3x the output tokens Luna did to run the index, so at equal per-token prices
it likely costs more per task. Haiku is first in the order for the higher
score and speed. The script has no switch to put Luna first for bulk,
cost-sensitive runs; add one if the token gap shows up in practice. Anthropic's Haiku 5.5 guide also warns it can report code as done
without running a check, so ask the delegate to run and show its tests. GPT-5.6
Luna scores 37 at max effort, and Haiku 4.5 (legacy) 15.

What the numbers don't capture: a Claude sub-agent shares this session's tool
access, skill injection, and structured output conventions natively: Copilot
delegation is an external CLI call with its own profile system, no shared
context, and output that must be reviewed as untrusted (see "Rules" below).
Where the Claude and Copilot balances are separate (the work laptop, see
below), reverse the default: reach for `delegate.sh` first for anything
self-contained enough to hand off, including code from a clear spec, tests
it runs itself and sweeps, and use a Claude sub-agent only for what needs
this session's MCP tools or context. Elsewhere, prefer a Claude sub-agent
for anything needing tight integration with this session's tools, and reach
for `delegate.sh` when the task is self-contained enough to hand off as plain
text and either cost is the binding constraint or the user's context calls
for it.

## Separately metered Claude and Copilot allowances

When Claude and Copilot draw from separate allowances the user values
unevenly — a work seat with its own fixed monthly quota for each, priced or
capped independently of the other — prefer `delegate.sh` (Luna) over a
Claude haiku sub-agent for haiku-shaped work specifically, to conserve the
Claude allowance for sonnet/opus-tier judgement work it can't be substituted
for. Haiku 5.5's lower price does not weaken this on the work laptop: the two
balances are separate, so the Copilot delegate stays the first rung there. This is a policy
for that account shape, not a universal default: on a single pooled
per-token budget (Anthropic's API billed directly, or a personal account
with no separate Copilot allowance to protect), Luna no longer has a price
advantage over Haiku 5.5 and there's no allowance to conserve, so default to
the Claude haiku sub-agent and use Copilot only when the task suits the
integration trade-off in "What the numbers don't capture".

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
follows the same conventions this session does. Copilot discovers the shared
`home/skills/` families on its own through `~/.agents/skills` (see the
`skill-authoring` skill's wiring.md), but not skills that exist only in
Claude's `~/.claude/skills/`, and naming the skill makes the delegate read it
rather than hoping it fires. The script resolves each skill's directory (project
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
- `read-shell` — read, plus read-only commands: `git status/diff/log/show`,
  `rg`, `fd`, `jq`, `grep`, `head`, `tail`, `sort`, `diff`, `wc`, `ls`,
  `gh pr|issue|run list|view` (`gh pr diff` too), `kubectl get|describe|logs`
  and `sift`. Use for investigation: PR triage, log and metric queries,
  repo sweeps.
- `write-shell` — `read-shell` plus write, plus runners: `python3`, `pytest`,
  `cargo`, `npm test`/`npm run`, `nix`, `just`, `make`, `go`, `gofmt`,
  `golangci-lint`, `dotnet`, `tsc`, `shellcheck`, `bats`, `terraform
  fmt`/`validate`. Use for implement, run, fix loops. Run it in a worktree
  or a clean branch and review the diff: it can write anywhere under the
  working directory.

Both shell profiles deny `rm`, `sudo`, `git push`, `git reset`, and `gh pr
merge`/`close`/`api`. A deny rule beats an allow rule. `nix` is on the
`write-shell` list and can launch other commands (`nix shell -c ...`), so the
list limits a careless delegate but is not a sandbox for a hostile one.

Anything not on a list is refused: the delegate reports it as denied and
carries on without it. Add a one-off with
`DELEGATE_EXTRA_ALLOW_TOOL='shell(pup)'`, one value passed as one
`--allow-tool`. `gh api` stays denied because a `shell(gh api)` pattern also
matches `-X POST`; allow it by hand for a read-only task.

Facts measured on 2026-10-06 (copilot 1.0.88), so prompts can avoid the traps:

- Give each command as one simple command. `cd dir && cmd` was refused
  where `cmd dir` ran; pass the directory as an argument.
- A `shell(...)` entry matches by command prefix. `shell(nix shell)` was not
  enough to run `nix shell --impure --expr ... -c pytest`; `shell(nix)` was.
- A comma list inside one `shell(a,b,c)` dropped the first entry, so the
  script uses one `--allow-tool` per command.
- The delegate sees the working directory only. To read elsewhere, run from
  the repo that holds the files, or pass `--add-dir` by hand.
- `DELEGATE_REASONING_EFFORT=high` (or `none`, `minimal`, `low`, `medium`,
  `xhigh`, `max`) gives a harder task more thinking at the same low price.
  Try it before escalating to a Claude sub-agent.

## What Luna handled in testing

Same-day tests on a small fixture, `gpt-6-luna` and `gpt-5.6-luna`:

| Task | Result |
|---|---|
| Add `/healthz` and `/readyz` to an Express and a FastAPI service | Correct, both models |
| Add liveness, readiness and startup probes to two k8s manifests | Correct |
| Write pytest tests, then run and fix them (`write-shell`) | 4 to 5 tests, green |
| Review a seeded buggy health handler | Found both planted defects |
| Draft a Conventional Commits message | Correct |
| Sweep seven skills for the commands they use | Useful but incomplete: it missed `pup` and `sift`, and printed its table twice |

So hand it code, tests, config and drafts first, and read its sweeps and
reviews as a first pass, not a complete list.

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
