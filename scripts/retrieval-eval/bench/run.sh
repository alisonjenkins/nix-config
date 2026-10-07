#!/usr/bin/env bash
# Reproduces the memory-recall benchmarks (docs/memory-recall.md).
#
# Run from inside the dev shell, with the repo root as the working directory:
#   nix develop path:scripts/retrieval-eval --command \
#     env MEMORY_DIR=~/.claude/projects/<project>/memory \
#     scripts/retrieval-eval/bench/run.sh
#
# Starts and stops its own llama-server on $PORT, so stop any other server on
# that port first. Takes ~25 minutes; do not use the machine meanwhile, the
# timings are wall clock. Results land in $OUT (JSON, one file per benchmark).
set -euo pipefail

root=$(pwd)
crate=$root/scripts/retrieval-eval
out=${OUT:-$crate/bench/results}
mem=${MEMORY_DIR:?set MEMORY_DIR to a directory of memory *.md files}
skills=${SKILLS_ROOT:-$HOME/.claude/skills}
port=${PORT:-8110}
runs=${RUNS:-300}
bin=$crate/target/release
caches=$(mktemp -d)

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
model_dir=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.ali-desktop.pkgs.llama-models.embeddinggemma-2-q8-0)
model=$model_dir/embeddinggemma-2-Q8_0.gguf

jq -n \
  --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg cpu "$(lscpu | sed -n 's/^Model name:[[:space:]]*//p')" \
  --arg threads "$(nproc)" \
  --arg mem_kb "$(awk '/^MemTotal/ {print $2}' /proc/meminfo)" \
  --arg kernel "$(uname -r)" \
  --arg load "$(cut -d' ' -f1-3 /proc/loadavg)" \
  --arg llama "$llama" \
  --arg model "$model" \
  --argjson memories "$(find "$mem" -maxdepth 1 -name '*.md' ! -name MEMORY.md | wc -l)" \
  '{date: $date, cpu: $cpu, logical_cpus: ($threads|tonumber), mem_kb: ($mem_kb|tonumber),
    kernel: $kernel, loadavg_at_start: $load, llama_cpp: $llama, model: $model,
    memories: $memories}' >"$out/env.json"

spec() { echo "gemma=gemma@http://127.0.0.1:$port#$1"; }
recall() { # dims, then memory-recall subcommand
  local dims=$1
  shift
  "$bin/memory-recall" --memory-dir "$mem" --embedder "$(spec "$dims")" \
    --cache "$caches/gemma-$dims.json" "$@"
}
bench() { # dims, json name, then recall-bench args
  local dims=$1 name=$2
  shift 2
  "$bin/recall-bench" --memory-dir "$mem" --embedder "$(spec "$dims")" \
    --cache "$caches/gemma-$dims.json" --json "$out/$name.json" "$@"
}
queries=$crate/queries
# The memory query sets name real memories, so the ones in git are placeholders;
# point this at your own (see queries/README.md).
memory_queries=${MEMORY_QUERIES_DIR:-$queries}

echo "== cold start (page cache warm), 3 runs"
starts=()
for _ in 1 2 3; do
  start_server
  starts+=("$startup_secs")
  stop_server
done
jq -n '$ARGS.positional | map(tonumber) | {startup_secs: .}' --args "${starts[@]}" \
  >"$out/coldstart.json"

echo "== index every dimension (default threads)"
start_server
for dims in 768 512 256 128; do
  recall "$dims" index
done

echo "== retrieval quality: memories"
"$bin/retrieval-eval" --corpus memory --memory-dir "$mem" \
  --queries "$memory_queries/memory.json" --json "$out/quality-memory-dims.json" \
  --embedder "g768=gemma@http://127.0.0.1:$port#768" \
  --embedder "g512=gemma@http://127.0.0.1:$port#512" \
  --embedder "g256=gemma@http://127.0.0.1:$port#256" \
  --embedder "g128=gemma@http://127.0.0.1:$port#128" | tee "$out/quality-memory-dims.md"
"$bin/retrieval-eval" --corpus memory --memory-dir "$mem" \
  --queries "$memory_queries/memory.json" --json "$out/quality-memory-rrf.json" --rrf \
  --embedder "g256=gemma@http://127.0.0.1:$port#256" | tee "$out/quality-memory-rrf.md"

echo "== retrieval quality: skills"
"$bin/retrieval-eval" --corpus skills --skills-root "$skills" --skills programming,delegation \
  --queries "$queries/skills.json" --json "$out/quality-skills-dims.json" \
  --embedder "g768=gemma@http://127.0.0.1:$port#768" \
  --embedder "g256=gemma@http://127.0.0.1:$port#256" \
  --embedder "g128=gemma@http://127.0.0.1:$port#128" | tee "$out/quality-skills-dims.md"

echo "== injection threshold sweep"
for dims in 768 256 128; do
  bench "$dims" "gate-$dims" gate \
    --relevant "$memory_queries/memory.json" --negatives "$queries/negatives.json" |
    tee "$out/gate-$dims.md"
done

echo "== hook latency, default threads"
bench 256 latency-default latency --hook-bin "$bin/memory-recall" \
  --relevant "$memory_queries/memory.json" --negatives "$queries/negatives.json" \
  --runs "$runs" --server-pid "$server_pid" | tee "$out/latency-default.md"

echo "== index cost, default threads"
bench 256 index-default index | tee "$out/index-default.md"
stop_server

echo "== thread sweep"
for threads in 1 2 4 8 16; do
  start_server "$threads"
  bench 256 "latency-threads-$threads" latency --hook-bin "$bin/memory-recall" \
    --relevant "$memory_queries/memory.json" --negatives "$queries/negatives.json" \
    --runs 100 --server-pid "$server_pid" | tee "$out/latency-threads-$threads.md"
  if [ "$threads" = 4 ]; then
    bench 256 index-threads-4 index | tee "$out/index-threads-4.md"
  fi
  stop_server
done

echo "== scaling (no server)"
bench 256 scale scale | tee "$out/scale.md"

jq --arg end "$(cut -d' ' -f1-3 /proc/loadavg)" '. + {loadavg_at_end: $end}' \
  "$out/env.json" >"$out/env.json.tmp"
mv "$out/env.json.tmp" "$out/env.json"
echo "done: $out"
