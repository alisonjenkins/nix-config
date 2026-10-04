# Env from the nix check (flake-modules/minecraft-rcon-tests.nix):
#   SERVER_PROPERTIES  baked server.properties text
#   ENTRYPOINT         entrypoint.sh source
#   RCON_LIB           rcon.sh source (sourced here)
#   IMAGE_CONTENTS     file listing the image contents' package names

setup() {
  work="$(mktemp -d)"
  props="$work/server.properties"
}

teardown() {
  rm -rf "$work"
}

load_lib() {
  # shellcheck disable=SC1090
  source "$RCON_LIB"
}

@test "baked server.properties enables rcon on 25575" {
  grep -qx 'enable-rcon=true' "$SERVER_PROPERTIES"
  grep -qx 'rcon.port=25575' "$SERVER_PROPERTIES"
}

@test "baked server.properties carries no rcon password" {
  ! grep -E '^rcon\.password=.+' "$SERVER_PROPERTIES"
}

@test "baked server.properties does not set server-ip" {
  ! grep -E '^server-ip=' "$SERVER_PROPERTIES"
}

@test "image contents include mcrcon, bash and coreutils" {
  grep -qx 'mcrcon' "$IMAGE_CONTENTS"
  grep -qx 'bash' "$IMAGE_CONTENTS"
  grep -qx 'coreutils' "$IMAGE_CONTENTS"
}

@test "entrypoint configures rcon before exec'ing java" {
  cfg="$(grep -n 'configure_rcon' "$ENTRYPOINT" | tail -1 | cut -d: -f1)"
  run_line="$(grep -n '^exec java' "$ENTRYPOINT" | cut -d: -f1)"
  [ -n "$cfg" ]
  [ "$cfg" -lt "$run_line" ]
}

@test "unset RCON_PASSWORD fails fast with a clear error" {
  load_lib
  : > "$props"
  unset RCON_PASSWORD
  run configure_rcon "$props"
  [ "$status" -ne 0 ]
  [[ "$output" == *"RCON_PASSWORD"* ]]
  ! grep -q 'rcon.password' "$props"
}

@test "empty RCON_PASSWORD fails fast" {
  load_lib
  : > "$props"
  RCON_PASSWORD="" run configure_rcon "$props"
  [ "$status" -ne 0 ]
  [[ "$output" == *"RCON_PASSWORD"* ]]
}

@test "password with a newline is rejected" {
  load_lib
  : > "$props"
  RCON_PASSWORD=$'abc\nenable-rcon=false' run configure_rcon "$props"
  [ "$status" -ne 0 ]
}

@test "password is written, never echoed" {
  load_lib
  cp "$SERVER_PROPERTIES" "$props"
  RCON_PASSWORD="s3cr3t-value" run configure_rcon "$props"
  [ "$status" -eq 0 ]
  [[ "$output" != *"s3cr3t-value"* ]]
  grep -qx 'rcon.password=s3cr3t-value' "$props"
}

@test "special characters survive intact" {
  load_lib
  cp "$SERVER_PROPERTIES" "$props"
  pw='a/b&c\d|e=f+g$h"i'"'"'j k#l=='
  RCON_PASSWORD="$pw" run configure_rcon "$props"
  [ "$status" -eq 0 ]
  [ "$(grep '^rcon.password=' "$props")" = "rcon.password=$pw" ]
  [ "$(grep -c '^rcon.password=' "$props")" -eq 1 ]
}

@test "stale PVC copy is forced to rcon on with the new password, once" {
  load_lib
  printf 'enable-rcon=false\nrcon.port=1\nrcon.password=old\nmotd=keep me\n' > "$props"
  RCON_PASSWORD="new" run configure_rcon "$props"
  [ "$status" -eq 0 ]
  grep -qx 'enable-rcon=true' "$props"
  grep -qx 'rcon.port=25575' "$props"
  grep -qx 'rcon.password=new' "$props"
  grep -qx 'motd=keep me' "$props"
  [ "$(grep -c '^enable-rcon=' "$props")" -eq 1 ]
  [ "$(grep -c '^rcon.port=' "$props")" -eq 1 ]
  ! grep -q 'rcon.password=old' "$props"
}

@test "missing server.properties fails" {
  load_lib
  RCON_PASSWORD="x" run configure_rcon "$work/nope"
  [ "$status" -ne 0 ]
}
