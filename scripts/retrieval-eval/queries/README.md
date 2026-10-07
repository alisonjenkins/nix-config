# Query sets

| File | Holds | In git |
|---|---|---|
| `memory.json`, `facts.json`, `heldout-facts.json` | Questions, expected memory files and key facts for the memory benchmarks | **Placeholders.** Four synthetic questions about invented memories (`example-*.md`); they show the schema and nothing else. |
| `skills.json`, `skills-facts.json` | The same for the skill sections under `home/skills` | Real: the skills are in this repo. |
| `negatives.json` | Prompts no memory or skill should answer | Real: generic prompts. |

The real memory sets name a person's private notes, so they are not committed. Put
yours in `queries/private/` (git-ignored) with the same three file names and run the
drivers with

```bash
MEMORY_QUERIES_DIR=scripts/retrieval-eval/queries/private scripts/retrieval-eval/bench/compare.sh
```

Each query is `{"q": ..., "expect": ["<memory file>.md"]}`; `facts.json` and
`heldout-facts.json` add `"facts": [{"text": ..., "where": "description" | "body"}]`,
each a verbatim string from that file. `retrieval-eval --validate-only` fails if an
expected file no longer exists.

The saved results in `bench/results/` were produced on the real sets. Their question
text and memory file names are replaced by placeholders (`Example question N`,
`example-memory-N.md`); every number is unchanged.
