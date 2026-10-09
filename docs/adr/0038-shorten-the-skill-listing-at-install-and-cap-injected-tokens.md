# 0038. Shorten the skill listing at install, and cap injected tokens

- Status: Proposed. Built; `shortListing` is opt-in, enabled on `ali-desktop` for
  the trial. On held-out queries it finds the right skill more often than the full
  listing (97% against 83%).
- Date: 2026-10-08
- Amends [0031](0031-skill-hook-with-a-calibrated-floor-and-a-trial-log.md).

## Context

Claude Code puts every skill's name and description in every session. For the 39
skills on `ali-desktop` that is about 4,250 tokens by bytes divided by four, 5,800 by
the API's count, and it grows with every skill added; past 1% of the context window
Claude Code drops descriptions. Three questions came up: can a compressed form of
the text cost less, can the descriptions be cut, and what bounds the two hooks
together.

## Findings

- **A compressed language does not help.** The same listing counted by the API:
  English 5,808 tokens; telegraphic English 5,202 (-10%); Chinese 5,713 (-2%);
  base64 46,756 (+705%). The tokenizer spends about as many tokens on a Chinese
  character's meaning as on the English words that carry it, and byte encodings
  defeat its vocabulary (`bench/results/listing-encodings.md`).
- **Cutting descriptions loses the right skill.** With the model choosing from the
  listing and loading files, 1,536 characters picked the right skill 95% of the
  time, 500 characters 85%, 250 80%, 100 75%.
- **Margin gates do not reduce false injections for free.** A rule that injects only
  when the best score leads the runner-up by a margin lowers adjacent-prompt false
  injections only as far as it lowers recall. Raising the floor from 0.74 to 0.76
  does the same for less (`bench/results/gate-margin.md`). The gate is unchanged.

## Prior art (searched 2026-10-09)

Mostly single-author samples and secondhand figures; the strong claims are marked.

- **The failure is not invoking, not picking.** A sandboxed `claude -p` run (Sonnet
  4.5, 22 prompts) had skills activate on 50 to 55% of prompts with no hook and 100%
  with a hook that makes the model state YES or NO for each skill and then call it;
  a passive "consider skill X" hook was no better than none. Once a skill was
  activated the right one was chosen every time. Prompts naming a keyword activated
  about 100% unaided, conceptual ones about 0%
  (scottspence.com/posts/measuring-claude-code-skill-activation-with-sandboxed-evals).
  Taken here: the injected header asks for a decision, and the short description
  keeps the routing words.
- **Tool search.** Anthropic's tool search tool raised selection accuracy from 49% to
  74% (Opus 4) and 79.5% to 88.1% (Opus 4.5) with 8.7K tokens instead of 77K; its
  advice is clear descriptive definitions and a few always-loaded tools
  (anthropic.com/engineering/advanced-tool-use).
- **Retrieval for tools and skills.** RAG-MCP: 13.6% to 43.1% selection accuracy
  with retrieval (arxiv 2505.03275). Tool2Vec: embedding a tool as the mean of its
  example queries, up to +27 recall@K (arxiv 2409.02141). SkillRouter: hiding the
  skill body costs 31 to 44 points of routing accuracy (arxiv 2603.22455), which
  supports keeping the full text retrievable. HyDE-style rewrites did worse than
  plain dense retrieval on tools (arxiv 2408.01875).
- **Embedding and gating.** EmbeddingGemma's query and document prefixes (already
  used here) and Matryoshka 512 over 256 at about +0.8 MTEB points; absolute cosine
  cutoffs are weak abstention signals, and no tested margin rule was found, matching
  `bench/results/gate-margin.md` (arxiv 2609.15578). Doc2query appended to the same
  text can hurt dense retrieval; a separate vector per generated question, filtered
  by retrieving its own parent, is the safer form (arxiv 2301.03266).
- **Compression.** Telegraphic rewriting saves about 8.5% of output tokens in an
  independent 86-task run (infoworld.com/article/4193775); our 10% on the listing
  matches. No Claude-tokenizer evidence for LLMLingua or dictionary schemes.

## Decision

- **Install a short listing and keep the full text retrievable.** `skill-transform`
  rewrites each `SKILL.md` as Nix installs it: `description` becomes the author's
  `summary:` field or the first sentence cut at a word, within 100 characters, and
  the full description becomes a `## When to use` section the skills hook retrieves.
  Sources under `home/skills` stay as written. Bundled files stay symlinks. Skills
  that are already short, or hidden with `disable-model-invocation`, are not changed.
  `modules.memoryRecall.skills.shortListing.enable` turns it on and requires
  `skills.enable`, because without the hook the long text is unreachable.
- **Cap what the hooks add.** Each hook takes `--max-tokens` (module `maxTokens`,
  default 1,500 each) and drops lower-ranked matches past it, so together they stay
  under 3,000 tokens, below the roughly 3,100 the names-only catalogue saves.
- **Follow symlinks when reading skills and memories.** Installed skills are
  symlinks into the Nix store, and the walker skipped them: 97 of 753 sections were
  never indexed.
- **Audit the listing.** `skill-listing` reports the listing's tokens against a cap,
  what is left, and how long a description can be for a given skill count.

## How we know

`recall-compare skills --short-chars N` with sonnet, single runs
(`bench/results/short-listing.md`). The first design (first sentence cut at 100
characters, sections injected at the hook's 0.74 floor, the model free to open
files) found the right source for 85% of 20 dev queries against 95% for the full
listing. Four changes closed that, each tested: authored `metadata.summary` lines of
up to 160 characters that keep the routing words (the misses were all `programming`
language files); a header that asks the model to decide which sections apply;
one-line pointers for sections between 0.66 and the full floor; and 512 dimensions
with floors recalibrated (`bench/results/dims-512.md`: half the false injections at
the same recall, and top-3 skill recall 0.87 against 0.80 on held-out queries).
On 30 held-out queries written after the tuning, the shipped flow finds the right
source for 83% and the new setup for 97%, with more facts in the final context (96%
against 86%) and a lower cost per query ($0.069 against $0.075). The dev set gives
100% against 95%. The listing falls from 4,248 to 1,184 tokens by bytes divided by
four for the 39 skills installed on `ali-desktop`. The held-out miss is one query
(alert flapping) and the facts-in-answer column stays near 40% there because the
benchmark counts exact phrases.

Memory uses the same 512 dimensions: at the same recall the adjacent-prompt false
injections halve and precision rises 6 to 7 points (0.72 against the old 0.74), so
`bodyScore` moves to 0.74 and `minScore` stays 0.70.

## Revisit when

The trial log shows the model failing to find a skill the short listing hides, or a
skill is added whose first sentence says nothing about when to use it (give it a
`summary:`).
