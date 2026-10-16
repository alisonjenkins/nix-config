# Cost and speed by tier

Moved out of `SKILL.md`; read it when quoting a price or index figure, comparing
tiers numerically, or checking which model `model: "haiku"` runs.

Prices from [claude.com/pricing](https://claude.com/pricing); intelligence
index and output speed from [Artificial
Analysis](https://artificialanalysis.ai/providers/anthropic) (medium effort).
Both checked 2026-09-28 — verify current numbers before quoting them, since
this table will drift. The Haiku 5.5 row was checked 2026-10-08: price from
the Claude Code changelog, index and speed read from the Artificial Analysis
Anthropic page. The other rows' index figures date from 2026-09-28 and were
measured at medium effort unless noted, so compare Haiku 5.5's medium
figure with them:

| Tier | Input / output per MTok (million tokens) | Roughly vs. Haiku | AA intelligence index | Output tok/s |
|---|---|---|---|---|
| Haiku 5.5 (`claude-haiku-5-5`) | $0.10 / $0.50 | 1x | 34 at medium effort (29 low, 38 high, 43 max) | ~243 (max effort) |
| Haiku 4.5 (legacy) | $1 / $5 | ~10x | 15 | ~80 |
| Sonnet 5 | $2 / $10 | ~20x | 28 | ~60 |
| Opus 5.5 | $4 / $20 | ~40x | 51 (up to 58 at max effort) | ~82 |
| Fable 5.1 | $10 / $50 | ~100x | 49 (up to 53 at max effort) | ~56 |

Haiku 5.5 is the default Haiku on the Anthropic API: 1M context, and
$0.50 / $2.50 for prompts over 100K. It costs a tenth of Haiku 4.5 and scores
above Sonnet 5 on the index at medium effort (34 against 28), so the "haiku"
tier in this skill means 5.5. Anthropic positions it for classification,
extraction, routing and sub-agent tasks, and it is the first Haiku with
effort levels (default medium). Claude Code's docs list it as supported for
auto mode; Haiku 4.5 is not.

Which model `model: "haiku"` actually runs depends on the Claude Code
version. Haiku 5.5 became the default Haiku on the Anthropic API in 2.1.293;
on Bedrock, Vertex and Foundry the alias still resolves to 4.5. Before
2.1.293, which includes 2.1.286 (what was installed on 2026-10-08) and the
2.1.292 nixpkgs pinned then, expect 4.5 (inferred from the changelog, not stated by the docs). Check with
`claude --version`, and a pin via `ANTHROPIC_DEFAULT_HAIKU_MODEL` also lands
on whatever it names.

Known Haiku 5.5 weak spots, from Anthropic's prompting guide: at low or
medium effort it sometimes reports code as done without running a check, can
skip a search, and can stop early on a long agent prompt. Its safety
classifiers can return a `refusal` stop reason on benign security work. The
new tokenizer counts about 30% more tokens than Haiku 4.5 for the same text.
So ask for the check to be run and read its output.

Opus 5.5 replaced Opus 5 ($5 / $25, now listed under legacy models) and is
cheaper than it. The index shifts several points with effort/reasoning
settings, so compare tiers by rough gap, not exact integers; it also
measures benchmark reasoning, not long-running agentic work, which is where
Fable is positioned.

Haiku is the cheapest tier. Per that same pricing page, Opus's
base speed is not fast — it has an optional "fast mode" at double its own
price for roughly 2.5x the speed — and Fable is priced and positioned for
long-running agentic work, not quick bulk calls.

The gap compounds with volume: 50 haiku-tiered calls cost roughly what 2.5
sonnet-tiered ones would (Sonnet's ~20x table ratio) for work that doesn't
need sonnet's judgement — or ~1 opus-tiered one (~40x), if that's the
comparison at hand. That gap, not a stylistic preference for cheap models,
is the whole case for
delegating aggressively rather than defaulting every call to whatever tier
the main loop runs on.

GitHub Copilot CLI delegation moved to the same unit as this table —
since 2026-06 Copilot bills per-token in "AI Credits" ($0.01/credit) instead
of premium-request multipliers, so its models are directly $/MTok comparable
to Claude's, not a separate currency. Claude models cost the same through
Copilot as through Anthropic's own API — no markup. See
[delegate-to-copilot.md](delegate-to-copilot.md) for the comparison and when
it beats an Agent-tool sub-agent on price. (The multiplier system still
exists for legacy annual-plan subscribers who didn't move to usage billing,
but that plan doesn't get new models — check which billing mode an account
is on before assuming either applies.)
