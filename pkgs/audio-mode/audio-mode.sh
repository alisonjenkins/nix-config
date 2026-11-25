# Switch call/game audio between the Steam Frame (Steam Link vrlink nodes)
# and the desk setup (Scarlett headphones + EasyEffects mic chain).

FRAME_SINK="${AUDIO_MODE_FRAME_SINK:-vrlink-sink}"
FRAME_SOURCE="${AUDIO_MODE_FRAME_SOURCE:-vrlink-source}"
DESK_SINK="${AUDIO_MODE_DESK_SINK:-effect_input.binaural71}"
DESK_SOURCE="${AUDIO_MODE_DESK_SOURCE:-easyeffects_source}"

# Filter-chain and EasyEffects plumbing streams carry their own wiring; moving
# them would break the binaural sink and the noise-suppression chain.
INTERNAL_STREAM_RE='^(effect_(input|output)\.|ee_|easyeffects)'

usage() {
  cat <<USAGE
Usage: audio-mode <frame|desk|toggle|status>

  frame   Default sink/source -> ${FRAME_SINK} / ${FRAME_SOURCE}, move live streams
  desk    Default sink/source -> ${DESK_SINK} / ${DESK_SOURCE}, move live streams
  toggle  Switch to whichever mode is not active
  status  Print the active mode and the default sink/source
USAGE
}

log() { printf 'audio-mode: %s\n' "$*" >&2; }

notify() {
  notify-send --app-name=audio-mode --expire-time=3000 "Audio" "$1" || true
}

node_exists() {
  local kind="$1" name="$2"
  pactl list short "$kind" | cut -f2 | grep -Fxq "$name"
}

current_mode() {
  local sink
  sink="$(pactl get-default-sink)"
  if [[ "$sink" == "$FRAME_SINK" ]]; then
    echo frame
  else
    echo desk
  fi
}

# Prints the index of each client stream of the given kind (sink-inputs or
# source-outputs), skipping the internal plumbing streams.
client_streams() {
  local kind="$1"
  pactl -f json list "$kind" 2>/dev/null | jq -r --arg re "$INTERNAL_STREAM_RE" '
    .[]
    | select(((.properties["node.name"] // "") | test($re)) | not)
    | select((.properties["application.process.binary"] // "") != "easyeffects")
    | .index'
}

move_streams() {
  local kind="$1" target="$2" verb idx moved=0
  case "$kind" in
    sink-inputs) verb=move-sink-input ;;
    source-outputs) verb=move-source-output ;;
  esac
  while read -r idx; do
    [[ -n "$idx" ]] || continue
    if pactl "$verb" "$idx" "$target"; then
      moved=$((moved + 1))
    else
      log "event=move_failed kind=$kind stream=$idx target=$target"
    fi
  done < <(client_streams "$kind")
  log "event=moved kind=$kind count=$moved target=$target"
}

switch_to() {
  local mode="$1" sink source
  if [[ "$mode" == frame ]]; then
    sink="$FRAME_SINK"; source="$FRAME_SOURCE"
  else
    sink="$DESK_SINK"; source="$DESK_SOURCE"
  fi

  if ! node_exists sinks "$sink"; then
    log "event=missing_sink mode=$mode sink=$sink"
    notify "Can't switch to $mode: $sink is not present"
    exit 1
  fi
  if ! node_exists sources "$source"; then
    log "event=missing_source mode=$mode source=$source"
    notify "Can't switch to $mode: $source is not present"
    exit 1
  fi

  pactl set-default-sink "$sink"
  pactl set-default-source "$source"
  move_streams sink-inputs "$sink"
  move_streams source-outputs "$source"

  log "event=switched mode=$mode sink=$sink source=$source"
  if [[ "$mode" == frame ]]; then
    notify "Steam Frame (speakers and mic)"
  else
    notify "Desk (Scarlett headphones, EasyEffects mic)"
  fi
}

case "${1:-}" in
  frame | desk) switch_to "$1" ;;
  toggle)
    if [[ "$(current_mode)" == frame ]]; then switch_to desk; else switch_to frame; fi
    ;;
  status)
    printf 'mode=%s sink=%s source=%s\n' "$(current_mode)" \
      "$(pactl get-default-sink)" "$(pactl get-default-source)"
    ;;
  -h | --help) usage ;;
  *) usage >&2; exit 2 ;;
esac
