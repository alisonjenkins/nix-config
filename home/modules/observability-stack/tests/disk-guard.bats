#!/usr/bin/env bats
# The guard reports when the data directories pass the disk budget and never stops
# the collector. It records guard.json, notifies once per 24 h while over, and
# returns to ok only below 90% of the budget. podman is a stub that records its
# arguments, notify-send and osascript are fakes. GUARD is the path of
# observability-stack-guard.

setup() {
  work="$(mktemp -d)"
  export OBS_DATA_DIR="$work/data"
  export OBS_STATE_DIR="$work/state"
  export OBS_CAP_BYTES=1048576
  export OBS_METRICS_URL=""
  export OBS_NOTIFY_FALLBACK=""
  mkdir -p "$OBS_DATA_DIR/loki" "$OBS_DATA_DIR/tempo" "$OBS_DATA_DIR/prometheus" "$OBS_STATE_DIR" "$work/bin"

  calls="$work/calls"
  : > "$calls"
  cat > "$work/podman" <<EOF
#!/bin/sh
echo "\$@" >> "$calls"
[ -z "\$PODMAN_FAIL" ] && [ "\$1 \$2" != "\$PODMAN_FAIL_ON" ]
EOF
  chmod +x "$work/podman"
  export OBS_PODMAN="$work/podman"
  ln -s "$work/podman" "$work/bin/podman"

  notified="$work/notified"
  : > "$notified"
  export PATH="$work/bin:$PATH"
}

teardown() {
  rm -rf "$work"
}

fake_notifier() {
  cat > "$work/bin/$1" <<EOF
#!/bin/sh
echo "$1 \$*" >> "$notified"
exit \${NOTIFY_EXIT:-0}
EOF
  chmod +x "$work/bin/$1"
}

fill() {
  head -c "$1" /dev/zero > "$OBS_DATA_DIR/loki/blob"
}

field() {
  jq -r ".$1" "$OBS_STATE_DIR/guard.json"
}

write_state() {
  # write_state <state> [notified]
  if [ -n "${2:-}" ]; then
    printf '{"state":"%s","usedBytes":1,"capBytes":1048576,"updated":"2026-01-01T00:00:00Z","notified":"%s"}' "$1" "$2" > "$OBS_STATE_DIR/guard.json"
  else
    printf '{"state":"%s","usedBytes":1,"capBytes":1048576,"updated":"2026-01-01T00:00:00Z"}' "$1" > "$OBS_STATE_DIR/guard.json"
  fi
}

iso_hours_ago() {
  date -u -d "$1 hours ago" +%Y-%m-%dT%H:%M:%SZ
}

@test "under the cap writes guard.json with state ok and notifies nobody" {
  fake_notifier notify-send
  fill 4096
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = ok ]
  [ "$(field usedBytes)" -ge 4096 ]
  [ "$(field capBytes)" -eq 1048576 ]
  [[ "$(field updated)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  [ "$(jq -r 'keys | join(",")' "$OBS_STATE_DIR/guard.json")" = "capBytes,state,updated,usedBytes" ]
  [ ! -s "$notified" ]
}

@test "over the cap records over, never touches the collector and notifies once" {
  fake_notifier notify-send
  fill 1200000
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = over ]
  [ "$(field usedBytes)" -ge 1200000 ]
  [[ "$(field notified)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  [ ! -s "$calls" ]
  [ "$(wc -l < "$notified")" -eq 1 ]
  [[ "$(cat "$notified")" == "notify-send "* ]]
}

@test "a second run while over does not notify again inside 24 hours" {
  fake_notifier notify-send
  fill 1200000
  run "$GUARD"
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = over ]
  [ "$(wc -l < "$notified")" -eq 1 ]
  [ ! -s "$calls" ]
}

@test "still over after 24 hours notifies again" {
  fake_notifier notify-send
  write_state over "$(iso_hours_ago 25)"
  fill 1200000
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$notified")" -eq 1 ]
  [ "$(field notified)" != "$(iso_hours_ago 25)" ]
}

@test "over for 23 hours does not notify again" {
  fake_notifier notify-send
  write_state over "$(iso_hours_ago 23)"
  fill 1200000
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ ! -s "$notified" ]
}

@test "over between 90 and 100 percent stays over without a new notification" {
  fake_notifier notify-send
  write_state over "$(iso_hours_ago 1)"
  fill 1000000
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = over ]
  [ ! -s "$notified" ]
}

@test "between 90 and 100 percent from ok stays ok" {
  fake_notifier notify-send
  write_state ok
  fill 1000000
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = ok ]
  [ ! -s "$notified" ]
}

@test "back under 90 percent returns to ok" {
  fake_notifier notify-send
  write_state over "$(iso_hours_ago 1)"
  fill 400000
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = ok ]
  [ "$(jq 'has("notified")' "$OBS_STATE_DIR/guard.json")" = false ]
  [ ! -s "$notified" ]
  [ ! -s "$calls" ]
}

@test "going over again after recovering notifies again" {
  fake_notifier notify-send
  fill 1200000
  run "$GUARD"
  fill 400000
  run "$GUARD"
  fill 1200000
  run "$GUARD"
  [ "$(wc -l < "$notified")" -eq 2 ]
}

@test "a missing notify-send is fine" {
  fill 1200000
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = over ]
}

@test "a failing notify-send does not fail the run" {
  fake_notifier notify-send
  fill 1200000
  NOTIFY_EXIT=1 run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = over ]
}

@test "a failing notify-send records no notified time, so the next run retries" {
  fake_notifier notify-send
  fill 1200000
  NOTIFY_EXIT=1 run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = over ]
  [ "$(jq 'has("notified")' "$OBS_STATE_DIR/guard.json")" = false ]
  run "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$(field notified)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  [ "$(wc -l < "$notified")" -eq 2 ]
}

@test "a failing osascript records no notified time" {
  fake_notifier osascript
  fill 1200000
  NOTIFY_EXIT=1 run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(jq 'has("notified")' "$OBS_STATE_DIR/guard.json")" = false ]
}

@test "a store that du cannot fully read still gets a guard.json with the partial size" {
  fill 4096
  mkdir "$OBS_DATA_DIR/tempo/locked"
  head -c 8192 /dev/zero > "$OBS_DATA_DIR/tempo/locked/blob"
  chmod 000 "$OBS_DATA_DIR/tempo/locked"
  run "$GUARD"
  chmod 755 "$OBS_DATA_DIR/tempo/locked"
  [ "$status" -eq 0 ]
  [ "$(field state)" = ok ]
  [ "$(field usedBytes)" -ge 4096 ]
}

@test "the guard can reach notify-send on a desktop without it on the unit PATH" {
  grep -q libnotify "$GUARD"
}

@test "osascript is used when notify-send is absent" {
  fake_notifier osascript
  fill 1200000
  run "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$(cat "$notified")" == "osascript -e display notification "* ]]
}

@test "an unreadable guard.json is treated as ok and rewritten" {
  printf 'not json' > "$OBS_STATE_DIR/guard.json"
  fill 4096
  run "$GUARD"
  [ "$status" -eq 0 ]
  [ "$(field state)" = ok ]
}

@test "no temporary file is left behind" {
  fill 1200000
  run "$GUARD"
  [ "$(ls "$OBS_STATE_DIR")" = guard.json ]
}

@test "the pushed metrics carry over_budget, used_bytes and cap_bytes" {
  fill 1200000
  python3 -c "
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        open('$work/pushed', 'wb').write(body)
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(('127.0.0.1', 0), H)
print(s.server_port, flush=True)
s.handle_request()
" > "$work/server.out" &
  server=$!
  for _ in $(seq 50); do [ -s "$work/server.out" ] && break; sleep 0.1; done
  OBS_METRICS_URL="http://127.0.0.1:$(cat "$work/server.out")/" run "$GUARD"
  wait "$server"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.resourceMetrics[0].scopeMetrics[0].metrics | map(.name) | sort | join(",")' "$work/pushed")" = "observability.guard.cap_bytes,observability.guard.over_budget,observability.guard.used_bytes" ]
  [ "$(jq -r '.resourceMetrics[0].scopeMetrics[0].metrics[] | select(.name == "observability.guard.over_budget") | .gauge.dataPoints[0].asInt' "$work/pushed")" = 1 ]
}

# RUN is observability-stack-run built with ports.grafana = $RUN_PORT.
run_stack() {
  OBS_DATA_DIR="$work/rundata" run "$RUN"
}

@test "starting the stack leaves guard.json alone" {
  write_state over "$(iso_hours_ago 1)"
  before="$(cat "$OBS_STATE_DIR/guard.json")"
  PODMAN_FAIL_ON="kube play" run_stack
  [ "$status" -ne 0 ]
  grep -q "^kube play" "$calls"
  [ "$(cat "$OBS_STATE_DIR/guard.json")" = "$before" ]
  [ ! -e "$OBS_STATE_DIR/guard.state" ]
}

@test "a port already in use stops the start and names the port and the option" {
  python3 -c "
import socket, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', $RUN_PORT))
s.listen(1)
print('ready', flush=True)
time.sleep(60)
" > "$work/listener.out" &
  listener=$!
  for _ in $(seq 50); do grep -q ready "$work/listener.out" && break; sleep 0.1; done
  run_stack
  kill "$listener" 2>/dev/null || true
  [ "$status" -eq 1 ]
  [[ "$output" == *"port $RUN_PORT is already in use"* ]]
  [[ "$output" == *"modules.observabilityStack.ports.grafana"* ]]
  if grep -q "^kube play" "$calls"; then false; fi
}

# MACHINE is the machine step of the run script rendered for darwin with the machine
# obs-test, 3 CPUs, 5000 MiB, 40 GiB. The stub keeps the machine in files.
machine_stub() {
  cat > "$work/podman" <<EOT
#!/bin/sh
echo "\$@" >> "$calls"
case "\$1 \$2" in
  "machine inspect")
    [ -f "$work/machine-exists" ] || exit 1
    case "\$3" in --format) cat "$work/machine-state" ;; esac ;;
  "machine init") touch "$work/machine-exists"; echo stopped > "$work/machine-state" ;;
  "machine start") echo running > "$work/machine-state" ;;
  "machine list") [ -f "$work/machine-list" ] && cat "$work/machine-list" ;;
esac
EOT
}

# Hide the machine-list probe from assertions about the lifecycle calls.
lifecycle_calls() {
  grep -v "^machine list" "$calls"
}

@test "a missing machine is inspected, created with the configured sizing, then started" {
  machine_stub
  run bash -c 'source "$MACHINE"'
  [ "$status" -eq 0 ]
  [ "$(lifecycle_calls | sed -n 1p)" = "machine inspect obs-test" ]
  [ "$(lifecycle_calls | sed -n 2p)" = "machine init --cpus 3 --memory 5000 --disk-size 40 obs-test" ]
  [ "$(lifecycle_calls | grep -c .)" -eq 4 ]
  [ "$(lifecycle_calls | sed -n 4p)" = "machine start obs-test" ]
}

@test "another machine running stops the start, names it and never starts ours" {
  machine_stub
  touch "$work/machine-exists"
  echo stopped > "$work/machine-state"
  printf 'obs-test false\npodman-machine-default* true\n' > "$work/machine-list"
  run bash -c 'source "$MACHINE"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"observability-stack: podman machine 'podman-machine-default' is running; podman runs one machine at a time on macOS. Stop it (podman machine stop podman-machine-default) or point modules.observabilityStack.podmanMachine.name at it."* ]]
  grep -qx "machine list --format {{.Name}} {{.Running}}" "$calls"
  if grep -q "machine start" "$calls"; then false; fi
}

@test "only our own machine listed as running does not trip the check" {
  machine_stub
  touch "$work/machine-exists"
  echo stopped > "$work/machine-state"
  printf 'obs-test* false\nother false\n' > "$work/machine-list"
  run bash -c 'source "$MACHINE"'
  [ "$status" -eq 0 ]
  grep -qx "machine start obs-test" "$calls"
}

@test "our machine already running passes without a conflict message" {
  machine_stub
  touch "$work/machine-exists"
  echo running > "$work/machine-state"
  printf 'obs-test* true\n' > "$work/machine-list"
  run bash -c 'source "$MACHINE"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"runs one machine"* ]]
}

@test "an existing stopped machine is started and never re-created" {
  machine_stub
  touch "$work/machine-exists"
  echo stopped > "$work/machine-state"
  run bash -c 'source "$MACHINE"'
  [ "$status" -eq 0 ]
  if grep -q "machine init" "$calls"; then false; fi
  grep -qx "machine start obs-test" "$calls"
}

@test "a running machine is neither created nor started" {
  machine_stub
  touch "$work/machine-exists"
  echo running > "$work/machine-state"
  run bash -c 'source "$MACHINE"'
  [ "$status" -eq 0 ]
  if grep -q "machine init" "$calls"; then false; fi
  if grep -q "machine start" "$calls"; then false; fi
}

@test "later podman calls are pointed at the dedicated machine" {
  machine_stub
  touch "$work/machine-exists"
  echo running > "$work/machine-state"
  run bash -c 'source "$MACHINE"; echo "$CONTAINER_CONNECTION"'
  [ "$status" -eq 0 ]
  [ "$output" = "obs-test" ]
}

@test "no machine call goes without the machine name" {
  machine_stub
  run bash -c 'source "$MACHINE"'
  [ "$status" -eq 0 ]
  if lifecycle_calls | grep -v "obs-test$" | grep -q .; then false; fi
}
