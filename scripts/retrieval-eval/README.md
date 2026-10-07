# retrieval-eval

Scores BM25 against embedding models on query -> expected-chunk pairs, over
Claude memory files (`--corpus memory`) or skill `##` sections
(`--corpus skills`). Decides whether embedding-based retrieval is worth
building for memories or skill references, and with which model.

Embedders are not linked in: the harness calls an OpenAI-compatible
`/v1/embeddings` endpoint, so any `llama-server --embeddings` works and the
model's source (Kaggle, Hugging Face, a local conversion) is just the file
the server loads.

The EmbeddingGemma 2 GGUF is `pkgs.llama-models.embeddinggemma-2-q8-0`
(`.modelFile`). It needs `pkgs.llama-cpp-upstream`: nixpkgs unstable (build
9190) and release v0.6.0 both fail with `unknown model architecture:
'gemma-embedding2'`.

```bash
# from the repo root
LLAMA=$(nix build --no-link --print-out-paths .#llama-cpp-upstream)
MODEL=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.ali-desktop.pkgs.llama-models.embeddinggemma-2-q8-0)
$LLAMA/bin/llama-server -m $MODEL/embeddinggemma-2-Q8_0.gguf --embeddings \
  -c 2048 -ub 2048 --port 8081 -ngl 0
```

## Run

```bash
cd scripts/retrieval-eval
nix develop path:. --command cargo test

# with the server above running
M=~/.claude/projects/-home-ali-git-personal-nix-config/memory
nix develop path:. --command cargo run --release -- \
  --corpus memory --memory-dir $M --queries queries/memory.json \
  --embedder gemma2=gemma@http://127.0.0.1:8081 \
  --embedder gemma2-256=gemma@http://127.0.0.1:8081#256 \
  --rrf --misses
```

`--embedder NAME=PRESET@URL[#DIMS]`: `gemma` wraps text in EmbeddingGemma's
retrieval prompts, `none` sends it as is; `#256` truncates (Matryoshka) and
re-normalises. One server serves one model, so compare models by running one
server per model on different ports.

`--validate-only` fails if a query expects a chunk id that no longer exists;
run it after memories or skills change. The queries are a snapshot of
2026-10-07 ground truth. The memory sets in git are placeholders; see
`queries/README.md`.

## memory-recall (prototype)

A `UserPromptSubmit` hook that injects the few memories closest to the prompt,
instead of the whole `MEMORY.md` index. Not wired into any settings.

```bash
BIN=target/release/memory-recall
ARGS="--memory-dir $M --embedder gemma2=gemma@http://127.0.0.1:8081#256 \
      --cache ~/.cache/memory-recall/gemma2-256.json"

$BIN $ARGS index                                  # embed new/edited memories (~70 s cold)
$BIN $ARGS query --top 3 "examplarr cannot log in"   # scores, for calibration
echo '{"prompt":"..."}' | $BIN $ARGS hook         # hook JSON on stdout
```

- `hook` embeds only the prompt (~20 ms) and reads document vectors from the
  cache; run `index` after memories change (unindexed ones are skipped with a
  warning). The cache is keyed by the server's model name, so swapping models
  discards it instead of ranking on incompatible vectors.
- It never fails a prompt: no server, a 3 s timeout, a payload with no
  prompt, or a prompt under 12 characters all inject nothing and exit 0.
- `--min-score` defaults to 0.74, measured for EmbeddingGemma 2 at 256 dims:
  correct matches scored 0.746-0.865, unrelated prompts 0.534-0.722. Re-measure
  after changing model or dims.
