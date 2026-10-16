# The per-machine ladder, in detail

Moved out of `SKILL.md`; the machine table and the rule to review first-rung
output stay there. Read this when choosing the first rung on the work machine
(Copilot / Luna) or a personal machine (local model), or when a first-rung call
fails.

The local first rung is text in, text out (its agent mode adds read, and
optionally edit, over one directory) and runs no commands. Luna can run an
allowlisted set of commands through `delegate.sh`'s `read-shell` and
`write-shell` profiles (see [delegate-to-copilot.md](delegate-to-copilot.md)),
so on the work machine only MCP tools, anything outside those lists (`aws`,
`pup`, `kubectl apply`, `terraform plan`) go straight to a sub-agent. Needing
a Claude skill is not a reason to skip Luna: `delegate.sh` takes skill names
as its third argument and the delegate reads them.

On the work machine the Claude balance is the scarce one and Copilot's is
separate, so the default is to hand Luna the work, not to ask whether it is
worth a sub-agent. The thresholds in "When to delegate at all" (two or more
calls, spawn overhead) are for Claude sub-agents. Luna is one Bash call whose
only Claude cost is the prompt you write and the reply you read, so a single
self-contained step qualifies.

Luna-shaped work on the work machine, tried before any haiku or sonnet
sub-agent: writing or editing code from a clear spec, writing tests and
running them (`write-shell`), config and manifest edits, commit and PR text
drafts, first-pass reviews, repo and log sweeps (`read-shell`), and format
conversion. Pass the `programming` or `testing` skill by name for code work.
It sometimes misses items in a sweep, so read its result before relying on it;
raise `DELEGATE_REASONING_EFFORT` before moving up a tier. Only a wrong result
at high reasoning effort, or a task needing judgement you cannot write down,
moves it up to a sonnet sub-agent.

On a personal machine the same default applies: send local-shaped work to
the local model and the rest to a haiku sub-agent, rather than doing it
inline. Local-shaped work is text-in/text-out drafts, summaries and format
conversion, and, through `delegate-to-local-agent.sh`, reads and edits over
one directory from an exact spec (with a diff to review). A single
self-contained step qualifies; the two-call threshold is no longer the bar.
Check `list-local-profiles.sh` first; it is read-only and cheap. If no
profile is live and local-shaped work is in front of you, load one instead
of falling straight to haiku: run `switch-local-profile.sh <profile>` with
`run_in_background` (up to two minutes), give the first step to a haiku
sub-agent meanwhile, and use the local model from the next step. Load it
once and leave it loaded for the session; the switch's VRAM fit check
refuses a profile that won't fit beside a game and names one that does, so a
refusal is the signal to use haiku, not a reason to avoid trying. Don't load
for a single one-off step you could hand to haiku in the time it takes (see
[delegate-to-local.md](delegate-to-local.md)). On the work machine, a
credit-exhaustion error from `delegate.sh` is cached for 24h, so after one,
go straight to haiku for the rest of the session.

Haiku 5.5 ($0.10 / $0.50) now costs the same as GPT-6 Luna, the cheapest
GPT model in Copilot, so the first rung no longer wins on price alone. Its edges
are zero marginal cost (local) and, on the work machine, Copilot's separate
credit pool: Claude and Copilot are metered apart there, so keep offloading
Luna-shaped work to Luna to conserve the Claude balance for sonnet/opus
judgement work. Haiku 5.5's lower price does not change that ladder. On a
personal machine with no live local profile, or where the task needs this
session's tools or skills, a haiku sub-agent is the better choice.

## What the local rung did on ali-desktop

On ali-desktop, a 35B mixture-of-experts model and a 9B wrote new modules,
unit tests and multi-edit changes from an exact spec, read-before-write and
test-passing (see the scorecard in
[delegate-to-local.md](delegate-to-local.md)), and only the 27B says correctly
what code does. So it takes spec'd code, tests, drafts, summaries and
extraction, not "explain what this does", with every result reviewed by a diff
or a test run.
