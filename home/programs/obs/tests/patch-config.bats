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
