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
