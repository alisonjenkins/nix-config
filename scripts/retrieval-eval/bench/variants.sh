#!/usr/bin/env bash
# Reproduces the retrieval-variants experiment (docs/memory-recall.md): which way of
# embedding a memory, which query prompt and which fusion finds the right memory best,
# tuned on the dev queries and judged on the held-out ones.
#
# Run from inside the dev shell, with the repo root as the working directory:
#   nix develop path:scripts/retrieval-eval --command \
#     env MEMORY_DIR=~/.claude/projects/<project>/memory \
#     scripts/retrieval-eval/bench/variants.sh
#
# Embeds ~700 document variants (~12 minutes on 4 threads), then restarts the server
# before scoring, because a server that has bulk-embedded keeps ~2 GB of compute
# buffers. Set CPUSET=24-31 (any cpu list) to pin the server if the machine is busy.
set -euo pipefail

root=$(pwd)
crate=$root/scripts/retrieval-eval
out=${OUT:-$crate/bench/results}
mem=${MEMORY_DIR:?set MEMORY_DIR to a directory of memory *.md files}
port=${PORT:-8110}
bin=$crate/target/release
queries=$crate/queries
# The memory query sets name real memories, so the ones in git are placeholders;
# point this at your own (see queries/README.md).
memory_queries=${MEMORY_QUERIES_DIR:-$queries}
caches=$(mktemp -d)

# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$crate/bench/lib.sh"

cleanup() {
  [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$caches"
}
trap cleanup EXIT

mkdir -p "$out"
cargo build --release --quiet --manifest-path "$crate/Cargo.toml"
llama=$(nix build --no-link --print-out-paths .#llama-cpp-upstream)
model_dir=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.ali-desktop.pkgs.llama-models.embeddinggemma-2-q8-0)
model=$model_dir/embeddinggemma-2-Q8_0.gguf

experiment=("$bin/recall-experiment" --memory-dir "$mem" --url "http://127.0.0.1:$port"
  --dims 256 --cache-dir "$caches"
  --dev "$memory_queries/memory.json" --heldout "$memory_queries/heldout-facts.json"
  --negatives "$queries/negatives.json")

echo "== embed every document variant"
start_server 4
"${experiment[@]}" --index-only
stop_server

echo "== score the prompts on a fresh server"
start_server 4
"${experiment[@]}" --json "$out/retrieval-variants.json" | tee "$out/retrieval-variants.md"
echo "done: $out"
