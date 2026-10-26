#!/usr/bin/env bats

setup() {
  run() { "$@"; }
  warnEcho() { echo "WARN: $*" >&2; }
  OBS_CRUDINI=crudini
  OBS_JQ=jq
  source "$BATS_TEST_DIRNAME/../patch-config.sh"

  dir="$BATS_TEST_TMPDIR"
  declared="$dir/declared.json"
  echo '{"type":"rtmp_custom","settings":{"server":"rtmp://example/app"}}' > "$declared"
}

@test "ini: declared keys are written in OBS's Key=value format" {
  obsPatchIni "$dir/new/basic.ini" Output Mode Advanced AdvOut Encoder vaapi
  grep -qx 'Mode=Advanced' "$dir/new/basic.ini"
  grep -qx 'Encoder=vaapi' "$dir/new/basic.ini"
}

@test "ini: undeclared keys survive and a drifted key is restored" {
  printf '[Output]\nMode=Simple\n\n[BasicWindow]\ngeometry=abc\n' > "$dir/basic.ini"
  obsPatchIni "$dir/basic.ini" Output Mode Advanced
  grep -qx 'Mode=Advanced' "$dir/basic.ini"
  grep -qx 'geometry=abc' "$dir/basic.ini"
}

@test "json: merges into an existing file, keeping undeclared keys" {
  echo '{"type":"rtmp_common","settings":{"key":"KEEP"}}' > "$dir/service.json"
  obsPatchJson "$dir/service.json" "$declared" "" ""
  [ "$(jq -r .type "$dir/service.json")" = rtmp_custom ]
  [ "$(jq -r .settings.server "$dir/service.json")" = rtmp://example/app ]
  [ "$(jq -r .settings.key "$dir/service.json")" = KEEP ]
}

@test "json: a missing file is created from the declared settings" {
  obsPatchJson "$dir/sub/service.json" "$declared" "" ""
  [ "$(jq -r .settings.server "$dir/sub/service.json")" = rtmp://example/app ]
}

@test "json: an empty file is treated as {} and patched" {
  : > "$dir/service.json"
  obsPatchJson "$dir/service.json" "$declared" "" ""
  [ "$(jq -r .settings.server "$dir/service.json")" = rtmp://example/app ]
}

@test "json: invalid JSON is left untouched" {
  echo '{broken' > "$dir/service.json"
  obsPatchJson "$dir/service.json" "$declared" "" "" 2>/dev/null
  [ "$(cat "$dir/service.json")" = '{broken' ]
}

@test "json: the secret is read from its file, without the trailing newline" {
  printf 'SECRET\n' > "$dir/key"
  obsPatchJson "$dir/service.json" "$declared" .settings.key "$dir/key"
  [ "$(jq -r .settings.key "$dir/service.json")" = SECRET ]
}

@test "json: an unreadable secret file keeps the existing secret" {
  echo '{"settings":{"key":"KEEP"}}' > "$dir/service.json"
  obsPatchJson "$dir/service.json" "$declared" .settings.key "$dir/missing" 2>/dev/null
  [ "$(jq -r .settings.key "$dir/service.json")" = KEEP ]
}

@test "json: patched files are private" {
  obsPatchJson "$dir/service.json" "$declared" "" ""
  [ "$(stat -c %a "$dir/service.json")" = 600 ]
}

@test "source: replaces id and settings of the named source only" {
  echo '{"name":"Untitled","sources":[{"name":"Webcam source","id":"v4l2_input","settings":{"device":"/dev/video0","resolution":"1080p"}},{"name":"Mic","id":"pulse_input_capture","settings":{"device_id":"default"}}]}' > "$dir/scene.json"
  echo '{"device_id":"v4l2_input.node"}' > "$dir/settings.json"
  obsPatchSource "$dir/scene.json" "Webcam source" pipewire-camera-source "$dir/settings.json"
  [ "$(jq -r '.sources[0].name' "$dir/scene.json")" = "Webcam source" ]
  [ "$(jq -r '.sources[0].id' "$dir/scene.json")" = pipewire-camera-source ]
  [ "$(jq -c '.sources[0].settings' "$dir/scene.json")" = '{"device_id":"v4l2_input.node"}' ]
}

@test "source: other sources and the rest of the collection are untouched" {
  echo '{"name":"Untitled","sources":[{"name":"Webcam source","id":"v4l2_input","settings":{}},{"name":"Mic","id":"pulse_input_capture","settings":{"device_id":"default"}}]}' > "$dir/scene.json"
  echo '{"device_id":"v4l2_input.node"}' > "$dir/settings.json"
  obsPatchSource "$dir/scene.json" "Webcam source" pipewire-camera-source "$dir/settings.json"
  [ "$(jq -c '.sources[1]' "$dir/scene.json")" = '{"name":"Mic","id":"pulse_input_capture","settings":{"device_id":"default"}}' ]
  [ "$(jq -r '.name' "$dir/scene.json")" = Untitled ]
}

@test "source: a name with no match leaves the file byte-identical" {
  echo '{"sources":[{"name":"Mic","id":"pulse_input_capture","settings":{}}]}' > "$dir/scene.json"
  cp "$dir/scene.json" "$dir/before.json"
  echo '{"device_id":"x"}' > "$dir/settings.json"
  obsPatchSource "$dir/scene.json" "Webcam source" pipewire-camera-source "$dir/settings.json" 2>/dev/null
  cmp "$dir/scene.json" "$dir/before.json"
}

@test "source: invalid JSON is left untouched" {
  echo '{broken' > "$dir/scene.json"
  echo '{"device_id":"x"}' > "$dir/settings.json"
  obsPatchSource "$dir/scene.json" "Webcam source" pipewire-camera-source "$dir/settings.json" 2>/dev/null
  [ "$(cat "$dir/scene.json")" = '{broken' ]
}

@test "audio slot: id, name and settings are replaced, the rest of the slot kept" {
  echo '{"DesktopAudioDevice1":{"name":"Desktop Audio","id":"pulse_output_capture","versioned_id":"pulse_output_capture","settings":{"device_id":"default"},"volume":0.5},"AuxAudioDevice1":{"name":"Mic/Aux","id":"pulse_input_capture"}}' > "$dir/scene.json"
  echo '{"TargetName":"obs-game"}' > "$dir/settings.json"
  obsPatchAudioSlot "$dir/scene.json" DesktopAudioDevice1 "Game Audio" pipewire-audio-capture-application "$dir/settings.json"
  [ "$(jq -r '.DesktopAudioDevice1.id' "$dir/scene.json")" = pipewire-audio-capture-application ]
  [ "$(jq -r '.DesktopAudioDevice1.versioned_id' "$dir/scene.json")" = pipewire-audio-capture-application ]
  [ "$(jq -r '.DesktopAudioDevice1.name' "$dir/scene.json")" = "Game Audio" ]
  [ "$(jq -c '.DesktopAudioDevice1.settings' "$dir/scene.json")" = '{"TargetName":"obs-game"}' ]
  [ "$(jq -r '.DesktopAudioDevice1.volume' "$dir/scene.json")" = 0.5 ]
  [ "$(jq -r '.AuxAudioDevice1.id' "$dir/scene.json")" = pulse_input_capture ]
}

@test "audio slot: an absent slot leaves the file byte-identical" {
  echo '{"AuxAudioDevice1":{"name":"Mic/Aux"}}' > "$dir/scene.json"
  cp "$dir/scene.json" "$dir/before.json"
  echo '{}' > "$dir/settings.json"
  obsPatchAudioSlot "$dir/scene.json" DesktopAudioDevice1 x y "$dir/settings.json" 2>/dev/null
  cmp "$dir/scene.json" "$dir/before.json"
}

# One scene holding one source, written the way OBS writes them.
scene_fixture() {
  cat > "$dir/scene.json" <<'JSON'
{"name":"Untitled","scene_order":[{"name":"Coding"}],"sources":[
 {"name":"Term","uuid":"u-term","id":"pipewire-screen-capture-source","versioned_id":"pipewire-screen-capture-source","settings":{"RestoreToken":"keep-me"},"mixers":0,"hotkeys":{},"volume":1.0},
 {"name":"Coding","uuid":"u-coding","id":"scene","versioned_id":"scene","mixers":0,"canvas_uuid":"canvas","hotkeys":{"OBSBasic.SelectScene":[],"libobs.show_scene_item.1":[],"libobs.hide_scene_item.1":[]},
  "settings":{"id_counter":1,"custom_size":false,"items":[{"name":"Term","source_uuid":"u-term","id":1,"visible":true,"bounds_type":2}]}}]}
JSON
  cat > "$dir/specs.json" <<'JSON'
[{"name":"Desktop screen","id":"pipewire-screen-capture-source","settings":{},"audio":false},
 {"name":"Desktop audio","id":"pipewire-audio-capture-application","settings":{"ExceptApp":true},"audio":true}]
JSON
}

@test "scene: creates the scene, its sources and its items" {
  scene_fixture
  obsEnsureScene "$dir/scene.json" Desktop "$dir/specs.json"
  [ "$(jq -r '[.scene_order[].name] | join(",")' "$dir/scene.json")" = Coding,Desktop ]
  [ "$(jq -r '.sources[] | select(.name=="Desktop audio") | .id' "$dir/scene.json")" = pipewire-audio-capture-application ]
  [ "$(jq -r '.sources[] | select(.name=="Desktop audio") | .mixers' "$dir/scene.json")" = 255 ]
  [ "$(jq -r '.sources[] | select(.name=="Desktop screen") | .mixers' "$dir/scene.json")" = 0 ]
  [ "$(jq -r '.sources[] | select(.name=="Desktop") | .canvas_uuid' "$dir/scene.json")" = canvas ]
  [ "$(jq -r '.sources[] | select(.name=="Desktop") | [.settings.items[].name] | join(",")' "$dir/scene.json")" = "Desktop screen,Desktop audio" ]
  [ "$(jq -r '.sources[] | select(.name=="Desktop") | .settings.id_counter' "$dir/scene.json")" = 2 ]
}

@test "scene: each item points at its source's uuid, and uuids are unique" {
  scene_fixture
  obsEnsureScene "$dir/scene.json" Desktop "$dir/specs.json"
  [ "$(jq -r '[.sources[].uuid] | unique | length' "$dir/scene.json")" = "$(jq '.sources | length' "$dir/scene.json")" ]
  [ "$(jq -r '.sources[] | select(.name=="Desktop") | .settings.items[0].source_uuid' "$dir/scene.json")" = "$(jq -r '.sources[] | select(.name=="Desktop screen") | .uuid' "$dir/scene.json")" ]
}

@test "scene: running twice changes nothing" {
  scene_fixture
  obsEnsureScene "$dir/scene.json" Desktop "$dir/specs.json"
  cp "$dir/scene.json" "$dir/once.json"
  obsEnsureScene "$dir/scene.json" Desktop "$dir/specs.json"
  cmp "$dir/scene.json" "$dir/once.json"
}

@test "scene: an existing source keeps settings OBS wrote and takes the declared ones" {
  scene_fixture
  echo '[{"name":"Term","id":"pipewire-screen-capture-source","settings":{"ShowCursor":true},"audio":false}]' > "$dir/specs.json"
  obsEnsureScene "$dir/scene.json" Coding "$dir/specs.json"
  [ "$(jq -c '.sources[] | select(.name=="Term") | .settings' "$dir/scene.json")" = '{"RestoreToken":"keep-me","ShowCursor":true}' ]
  [ "$(jq -r '.sources[] | select(.name=="Coding") | .settings.items | length' "$dir/scene.json")" = 1 ]
}

@test "scene: a collection with nothing to copy from is left byte-identical" {
  echo '{"scene_order":[],"sources":[]}' > "$dir/scene.json"
  cp "$dir/scene.json" "$dir/before.json"
  echo '[{"name":"A","id":"x","settings":{},"audio":false}]' > "$dir/specs.json"
  obsEnsureScene "$dir/scene.json" Desktop "$dir/specs.json" 2>/dev/null
  cmp "$dir/scene.json" "$dir/before.json"
}
