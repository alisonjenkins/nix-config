#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2154,SC2034
# Shared by run.sh and compare.sh. Source it after setting: llama, model, port,
# out (a results directory). Provides start_server / stop_server and keeps
# $server_pid and $startup_secs.
#
# start_server must not run inside $(...): a subshell loses server_pid, the
# server is then never stopped, and later starts fail to bind while the health
# check passes against the orphan.

server_pid=""
startup_secs=""

# start_server [threads]
start_server() {
  if curl -fsS --max-time 1 "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    echo "something already answers on port $port; stop it first" >&2
    exit 1
  fi
  local args=(-m "$model" --embeddings -c 2048 -ub 2048 -ngl 0
    --host 127.0.0.1 --port "$port")
  [ -n "${1:-}" ] && args+=(--threads "$1")
  nice -n 10 "$llama/bin/llama-server" "${args[@]}" >"$out/server.log" 2>&1 &
  server_pid=$!
  local started
  started=$(date +%s.%N)
  until curl -fsS --max-time 1 "http://127.0.0.1:$port/health" >/dev/null 2>&1; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
      echo "llama-server exited early:" >&2
      tail -n 5 "$out/server.log" >&2
      exit 1
    fi
    sleep 0.1
  done
  startup_secs=$(awk -v a="$started" -v b="$(date +%s.%N)" 'BEGIN { printf "%.2f", b - a }')
}

stop_server() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  server_pid=""
}
