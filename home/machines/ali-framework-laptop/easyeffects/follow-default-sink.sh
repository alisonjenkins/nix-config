# EasyEffects 8.2.4 misses the default-sink change when it started while the
# new sink did not exist yet (a Bluetooth headset connecting after login), and
# keeps its output chain on the old sink. Re-setting the same default does
# nothing because PipeWire drops unchanged metadata, so bounce the default
# through EasyEffects' own sink, which it ignores and apps already play into.

readonly ee_output_node="ee_soe_output_level"
readonly ee_sink="easyeffects_sink"
# Long enough for EasyEffects to finish relinking on its own when it does notice.
readonly settle_seconds=3
readonly bounce_seconds=1

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

default_sink() {
  pw-metadata -n default 0 default.audio.sink \
    | sed -n "s/.*value:'\(.*\)' type:.*/\1/p" \
    | jq -r '.name // empty'
}

ee_output_targets() {
  pw-link -l | awk -v node="$ee_output_node" '
    index($0, node ":output_") == 1 { linked = 1; next }
    /^[^ ]/ { linked = 0 }
    linked && /\|->/ { sub(/^ *\|-> */, ""); sub(/:.*/, ""); print }
  ' | sort -u
}

node_id() {
  pw-dump | jq -r --arg name "$1" \
    '.[] | select(.type == "PipeWire:Interface:Node" and .info.props["node.name"] == $name) | .id' \
    | head -n 1
}

last_bounced=""

check() {
  local sink targets ee_id sink_id
  sink=$(default_sink)
  if [[ -z $sink || $sink == "$ee_sink" ]]; then return; fi
  if ! pw-link -o | grep -q "^${ee_output_node}:"; then return; fi

  targets=$(ee_output_targets)
  if [[ $targets == "$sink" ]]; then return; fi
  # No links means EasyEffects is idle; one bounce per sink is enough then.
  if [[ -z $targets && $sink == "$last_bounced" ]]; then return; fi

  ee_id=$(node_id "$ee_sink")
  sink_id=$(node_id "$sink")
  if [[ -z $ee_id || -z $sink_id ]]; then
    log "event=skip reason=node_missing sink=\"$sink\" ee_id=\"$ee_id\" sink_id=\"$sink_id\""
    return
  fi

  log "event=bounce sink=\"$sink\" ee_linked_to=\"${targets//$'\n'/,}\""
  wpctl set-default "$ee_id"
  sleep "$bounce_seconds"
  wpctl set-default "$sink_id"
  last_bounced=$sink
}

check
stdbuf -oL pw-metadata -m -n default | while IFS= read -r line; do
  if [[ $line == *"key:'default.audio.sink'"* ]]; then
    sleep "$settle_seconds"
    check
  fi
done
log "event=exit reason=metadata_monitor_ended"
exit 1
