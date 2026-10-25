# Sourced by home-manager activation, which provides `run` and `warnEcho`;
# the caller sets OBS_CRUDINI and OBS_JQ to the tools' paths.

# obsPatchIni TARGET [SECTION KEY VALUE]...
obsPatchIni() {
  local target="$1"; shift
  run mkdir -p "$(dirname "$target")"
  [ -e "$target" ] || run touch "$target"
  while [ "$#" -gt 0 ]; do
    run "$OBS_CRUDINI" --ini-options=nospace --set "$target" "$1" "$2" "$3"
    shift 3
  done
}

# obsPatchJson TARGET DECLARED_JSON SECRET_JQ_PATH SECRET_FILE
# The last two may be empty. The secret is read at run time so it never
# has to pass through the Nix store.
obsPatchJson() {
  local target="$1" declared="$2" secretPath="$3" secretFile="$4" tmp
  run mkdir -p "$(dirname "$target")"
  tmp=$(mktemp)
  if [ -n "$secretFile" ] && [ ! -r "$secretFile" ]; then
    warnEcho "obs: $secretFile unreadable, leaving the secret in $target unchanged"
    secretFile=""
  fi
  # A missing or empty target slurps to [], so it merges as {}.
  if "$OBS_JQ" -n \
      --slurpfile current "$([ -e "$target" ] && echo "$target" || echo /dev/null)" \
      --slurpfile declared "$declared" \
      --arg secretPath "$secretPath" \
      --rawfile secret "${secretFile:-/dev/null}" \
      --argjson hasSecret "$([ -n "$secretFile" ] && echo true || echo false)" '
    ($current[0] // {}) * $declared[0]
    | if $hasSecret
      then setpath($secretPath | ltrimstr(".") | split("."); $secret | rtrimstr("\n"))
      else . end
  ' > "$tmp"; then
    run install -m 0600 "$tmp" "$target"
  else
    warnEcho "obs: $target is not valid JSON, left unpatched"
  fi
  rm -f "$tmp"
}

# obsPatchSource TARGET SOURCE_NAME ID SETTINGS_JSON_FILE
# Sets the id and replaces the settings of the scene source named SOURCE_NAME.
# Settings are replaced, not merged: keys from the old source type are garbage.
obsPatchSource() {
  local target="$1" name="$2" id="$3" settings="$4" tmp
  if [ ! -e "$target" ]; then
    warnEcho "obs: $target does not exist, source $name left unpatched"
    return 0
  fi
  tmp=$(mktemp)
  if "$OBS_JQ" \
      --slurpfile settings "$settings" \
      --arg name "$name" \
      --arg id "$id" '
    if (.sources | map(select(.name == $name)) | length) == 0
    then error("no source named \($name)")
    else .sources |= map(if .name == $name then (.id = $id | .settings = $settings[0]) else . end)
    end
  ' "$target" > "$tmp"; then
    run install -m 0600 "$tmp" "$target"
  else
    warnEcho "obs: $target is not valid JSON or has no source $name, left unpatched"
  fi
  rm -f "$tmp"
}
