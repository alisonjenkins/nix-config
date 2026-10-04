# Sourced by entrypoint.sh. RCON settings are re-applied on every boot because
# the PVC copy of server.properties is only seeded on first start.

# set_property FILE KEY VALUE: replace KEY's line, or append it. Literal
# matching and printf keep `/ & \ |` in VALUE from being interpreted.
set_property() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  # KEY is a fixed literal from this file, so only its dots need escaping.
  grep -v -E "^${key//./\\.}=" "$file" >"$tmp" || true
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  # mv, not in-place write: the first-boot copy of the store file is read-only.
  chmod 644 "$tmp"
  mv -f "$tmp" "$file"
}

# configure_rcon FILE: enable RCON and set the password from $RCON_PASSWORD.
# Refuses to continue without a usable password; never prints it.
configure_rcon() {
  local file="$1"
  if [ -z "${RCON_PASSWORD:-}" ]; then
    echo "ERROR: RCON_PASSWORD is unset or empty; refusing to start with RCON enabled and no password" >&2
    return 1
  fi
  if [[ "$RCON_PASSWORD" == *$'\n'* || "$RCON_PASSWORD" == *$'\r'* ]]; then
    echo "ERROR: RCON_PASSWORD must be a single line" >&2
    return 1
  fi
  if [ ! -f "$file" ]; then
    echo "ERROR: server.properties not found at $file" >&2
    return 1
  fi
  set_property "$file" enable-rcon true
  set_property "$file" rcon.port 25575
  set_property "$file" rcon.password "$RCON_PASSWORD"
}
