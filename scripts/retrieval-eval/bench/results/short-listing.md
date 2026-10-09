# Short listing plus injected sections (spec 006, stories 7 and 8)

`recall-compare skills --short-chars N`: the skills as `skill-transform` installs them
(a short listing description, the full text as a `## When to use` section), their
sections embedded, and the best sections injected at the hook's floors. Sonnet,
single runs, 20 dev queries (`skills-facts.json`, used while tuning) and 30 held-out
queries (`skills-heldout-facts.json`, written afterwards and not tuned on).

The model sees the short listing in its system block and the sections in the user
turn, and may also pick a skill and open its reference files, as a session does
(`short_listing_hook_load`). `default_load` is the shipped flow: full listing, the
model loads skills and files.

## Where the setup came from (dev set, 256 dimensions)

| step | right source | facts in final context | facts in answer |
|---|---|---|---|
| default_load, full listing | 95% | 95% | 79% |
| short listing (100 characters, first sentence), top 3 always injected, no file loading | 85% | 79% | 70% |
| the same with the hook floor 0.74, no file loading | 65% | 64% | 59% |
| the same with file loading | 85% | 86% | 72% |
| the benchmark could not open files in the shortened tree (symlinks); fixed | 90% | 90% | 71% |
| authored summaries (160 characters), directive header | 90% | 90% | 78% |
| plus one-line pointers from 0.66 | 100% | 100% | 81% |

## Held-out check (30 queries not used for tuning)

| system | right source | facts in final context | facts in answer | model input tokens | $/query |
|---|---|---|---|---|---|
| default_load | 83% | 86% | 38% | 33,707 | 0.075 |
| short listing, summaries, pointers from 0.66, 256 dimensions | 97% | 97% | 42% | 21,253 | 0.071 |
| the same at 512 dimensions, full floor 0.72 | 97% | 96% | 39% | 21,161 | 0.069 |

Dev set at 512 dimensions and the same floors: 100% right source, 100% facts in
final context, 81% facts in answer, $0.104 a query (default_load: 95%, 95%, 79%,
$0.103).

The listing falls from 4,248 to 1,184 tokens by bytes divided by four for the 39
skills installed on `ali-desktop` (the benchmark's own 40-skill tree goes from
4,409 to 1,228).

## Reading it

- The facts-in-answer column is the model quoting the expected strings verbatim in a
  six-sentence answer; it sits well below facts in the final context everywhere, and
  low on the held-out set, whose facts are longer exact phrases. Facts in the final
  context is the part retrieval controls.
- The default misses 5 of 30 held-out queries (git signatures, operator
  preconditions, faking `gh` in bats, an env var that does not reach a process,
  skill-listing budget). The new setup misses 1 at 256 dimensions (the skill-listing
  budget again) and 1 at 512 (alert flapping, `observability/improving.md`).
- What did the work: authored summaries that keep the routing words (the three dev
  misses with the first-sentence cut were all `programming` language files), a header
  that asks the model to decide which sections apply, and one-line pointers for
  sections between 0.66 and the full floor, which tell the model which file to open
  for about 30 tokens each.
- Two benchmark faults found on the way, both fixed: the file walkers did not follow
  symlinks, so the shortened tree had no reference files to open, and 97 of 753
  sections were never indexed from a real install.
- Single runs at n=20 and n=30: one query is 3 to 5 points, and the same system moved
  4 points of facts in answer between two runs.
