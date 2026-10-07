#!/usr/bin/env bash
# Reproduces the memory and skills comparisons (docs/memory-recall.md): embedding
# retrieval against Claude's MEMORY.md index, cavemem, and the skill listing plus
# whole-file loading, scored on retrieval time, detail kept, tokens and answer
# quality.
#
# Run from inside the dev shell, with the repo root as the working directory:
#   nix develop path:scripts/retrieval-eval --command \
#     env MEMORY_DIR=~/.claude/projects/<project>/memory \
#     scripts/retrieval-eval/bench/compare.sh
#
# Starts and stops its own llama-server on $PORT. The model calls use your logged
# in `claude` (~$5 of API usage at the default settings: sonnet, ~50 queries,
# ~8 calls each); set NO_LLM=1 for the free retrieval-stage tables only.
set -euo pipefail

root=$(pwd)
crate=$root/scripts/retrieval-eval
out=${OUT:-$crate/bench/results}
mem=${MEMORY_DIR:?set MEMORY_DIR to a directory of memory *.md files}
skills=${SKILLS_ROOT:-$HOME/.claude/skills}
port=${PORT:-8110}
model_name=${MODEL:-sonnet}
bin=$crate/target/release
queries=$crate/queries
caches=$(mktemp -d)
extra=()
[ -n "${NO_LLM:-}" ] && extra+=(--no-llm)

# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$crate/bench/lib.sh"

cleanup() {
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$caches"
}
trap cleanup EXIT

mkdir -p "$out"

echo "== build"
cargo build --release --quiet --manifest-path "$crate/Cargo.toml"
llama=$(nix build --no-link --print-out-paths .#llama-cpp-upstream)
cavemem=$(nix build --no-link --print-out-paths .#cavemem)/bin/cavemem
model_dir=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.ali-desktop.pkgs.llama-models.embeddinggemma-2-q8-0)
model=$model_dir/embeddinggemma-2-Q8_0.gguf
db=${CAVEMEM_DB:-$HOME/.cavemem/data.db}

# Observations from today onwards include this very run's own session (it
# captures the commands and source it works on), so ignore them.
midnight_ms=$(($(date -u -d "$(date -u +%F)" +%s) * 1000))
cutoff=$(sqlite3 -readonly "$db" \
  "select coalesce(min(id), (select max(id) + 1 from observations)) from observations where ts >= $midnight_ms")
echo "cavemem cutoff id: $cutoff"

echo "== start the embedding server (4 threads, as the module runs it)"
start_server 4

embedder="gemma=gemma@http://127.0.0.1:$port#256"
echo "== index the memories"
"$bin/memory-recall" --memory-dir "$mem" --embedder "$embedder" \
  --cache "$caches/memory.json" index

# memory_compare FACTS OUT_BASENAME [SYSTEMS]: all systems when SYSTEMS is empty.
memory_compare() {
  local facts=$1 name=$2 systems=${3:-}
  local only=()
  [ -n "$systems" ] && only=(--systems "$systems")
  "$bin/recall-compare" --facts "$facts" --model "$model_name" \
    --json "$out/$name.json" "${extra[@]}" \
    memory --memory-dir "$mem" --hook-bin "$bin/memory-recall" \
    --embedder "$embedder" --cache "$caches/memory.json" \
    --cavemem-bin "$cavemem" --cavemem-db "$db" --sqlite-bin "$(command -v sqlite3)" \
    --cavemem-cutoff-id "$cutoff" "${only[@]}" | tee "$out/$name.md"
}

echo "== memory comparison, dev queries, every system"
memory_compare "$queries/facts.json" compare-memory

# The held-out queries were written without seeing any retrieval result; they
# are the honest check on settings tuned against the dev queries.
echo "== memory comparison, held-out queries"
memory_compare "$queries/heldout-facts.json" compare-memory-heldout \
  "default_read,default_open,recall_snippet,recall_read,recall_all,recall_auto_open,hybrid_open,slim_open"

echo "== skills comparison"
"$bin/recall-compare" --facts "$queries/skills-facts.json" --model "$model_name" \
  --json "$out/compare-skills.json" "${extra[@]}" \
  skills --skills-root "$skills" --embedder "$embedder" \
  --cache "$caches/skills.json" | tee "$out/compare-skills.md"

echo "done: $out"
