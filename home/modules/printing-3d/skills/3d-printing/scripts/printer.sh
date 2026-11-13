#!/usr/bin/env bash
# Control the Qidi printer over Moonraker (port 7125).
#   printer.sh status
#   printer.sh start FILE.gcode   (refuses unless the printer is idle)
#   printer.sh cancel
# The host comes from the Qidi Studio physical-printer config (print_host only;
# the key and password fields are never read).
set -euo pipefail

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found" >&2; exit 1; }

conf_dir="${QIDI_PRINTER_CONF_DIR:-$HOME/.config/QIDIStudio/user/default/physical_printer}"
host="${QIDI_PRINTER_HOST:-}"
if [[ -z "$host" ]]; then
  mapfile -t confs < <(find "$conf_dir" -maxdepth 1 -name '*.json' 2>/dev/null)
  [[ ${#confs[@]} -ge 1 ]] || { echo "no printer config in $conf_dir; set QIDI_PRINTER_HOST" >&2; exit 1; }
  [[ ${#confs[@]} -eq 1 ]] || { echo "${#confs[@]} printer configs in $conf_dir; set QIDI_PRINTER_HOST to pick one" >&2; exit 1; }
  conf="${confs[0]}"
  host="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["print_host"])' "$conf")"
fi
base="http://$host:7125"

state() {
  curl -fsS -m 10 "$base/printer/objects/query?print_stats&extruder&heater_bed&display_status" |
    python3 -I -c '
import json, sys
s = json.load(sys.stdin)["result"]["status"]
p, n, b = s["print_stats"], s["extruder"], s["heater_bed"]
pct = s["display_status"]["progress"] * 100
print("state=%s file=%s nozzle=%.0f/%.0f bed=%.0f/%.0f progress=%.0f%%"
      % (p["state"], p["filename"] or "-", n["temperature"], n["target"],
         b["temperature"], b["target"], pct))
'
}

case "${1:-}" in
  status)
    state ;;
  start)
    file="${2:?usage: printer.sh start FILE.gcode}"
    [[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 1; }
    current="$(state)"
    echo "$current"
    case "$current" in
      state=standby*|state=complete*|state=cancelled*) ;;
      *) echo "refusing to start: printer is not idle" >&2; exit 1 ;;
    esac
    curl -fsS -m 300 -F "file=@$file" -F "print=true" "$base/server/files/upload"
    echo
    state ;;
  cancel)
    curl -fsS -m 10 -X POST "$base/printer/print/cancel"
    echo
    state ;;
  *)
    echo "usage: printer.sh status | start FILE.gcode | cancel" >&2
    exit 2 ;;
esac
