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
    else .sources |= map(if .name == $name then (.id = $id | .versioned_id = $id | .settings = $settings[0]) else . end)
    end
  ' "$target" > "$tmp"; then
    run install -m 0600 "$tmp" "$target"
  else
    warnEcho "obs: $target is not valid JSON or has no source $name, left unpatched"
  fi
  rm -f "$tmp"
}

# obsPatchAudioSlot TARGET SLOT NAME ID SETTINGS_JSON_FILE
# Re-points a global audio slot (DesktopAudioDevice1, AuxAudioDevice1, ...) at
# another source kind. Settings are replaced, not merged, like obsPatchSource.
obsPatchAudioSlot() {
  local target="$1" slot="$2" name="$3" id="$4" settings="$5" tmp
  if [ ! -e "$target" ]; then
    warnEcho "obs: $target does not exist, audio slot $slot left unpatched"
    return 0
  fi
  tmp=$(mktemp)
  if "$OBS_JQ" \
      --slurpfile settings "$settings" \
      --arg slot "$slot" \
      --arg name "$name" \
      --arg id "$id" '
    if .[$slot] == null
    then error("no audio slot \($slot)")
    else .[$slot] |= (.name = $name | .id = $id | .versioned_id = $id | .settings = $settings[0])
    end
  ' "$target" > "$tmp"; then
    run install -m 0600 "$tmp" "$target"
  else
    warnEcho "obs: $target is not valid JSON or has no audio slot $slot, left unpatched"
  fi
  rm -f "$tmp"
}

# obsEnsureScene TARGET SCENE SPECS_JSON_FILE
# SPECS is a JSON list of {name, id, settings, audio}. Creates the scene and
# any source missing from the collection, and puts each source in the scene.
# An existing source keeps its other settings (a screen capture's portal
# RestoreToken must survive) and has the declared ones merged over them.
# New objects are copied from ones OBS already wrote, so the fields that
# vary between OBS versions are not hard-coded here.
obsEnsureScene() {
  local target="$1" scene="$2" specs="$3" tmp uuids count
  if [ ! -e "$target" ]; then
    warnEcho "obs: $target does not exist, scene $scene left uncreated"
    return 0
  fi
  count=$("$OBS_JQ" length "$specs")
  uuids=$(for _ in $(seq 0 "$count"); do cat /proc/sys/kernel/random/uuid; done | "$OBS_JQ" -Rn '[inputs]')
  tmp=$(mktemp)
  if "$OBS_JQ" \
      --slurpfile specs "$specs" \
      --arg scene "$scene" \
      --argjson uuids "$uuids" '
    ([.sources[] | select(.id == "scene")] | first) as $sceneTpl
    | ([.sources[] | select(.id == "scene") | .settings.items[]?] | first) as $itemTpl
    | ([.sources[] | select(.id != "scene" and .id != "group")] | first | del(.filters)) as $srcTpl
    | if $sceneTpl == null or $itemTpl == null or $srcTpl == null
      then error("collection has no scene, scene item and source to copy from")
      else . end
    | $specs[0] as $specs
    | reduce range(0; $specs | length) as $i (.;
        $specs[$i] as $s
        | if any(.sources[]; .name == $s.name)
          then .sources |= map(if .name == $s.name
              then .id = $s.id | .versioned_id = $s.id | .settings = ((.settings // {}) * $s.settings)
              else . end)
          else .sources += [$srcTpl
              | .name = $s.name | .uuid = $uuids[$i]
              | .id = $s.id | .versioned_id = $s.id | .settings = $s.settings
              | .mixers = (if $s.audio then 255 else 0 end)]
          end)
    | if any(.sources[]; .name == $scene)
      then .
      else .sources += [$sceneTpl
              | .name = $scene | .uuid = $uuids[$specs | length]
              | .hotkeys = {"OBSBasic.SelectScene": []}
              | .settings = {id_counter: 0, custom_size: false, items: []}]
           | .scene_order += [{name: $scene}]
      end
    | reduce $specs[] as $s (.;
        (.sources | map(select(.name == $s.name)) | first | .uuid) as $uuid
        | .sources |= map(if .name == $scene and (.settings.items | any(.name == $s.name) | not)
            then (.settings.id_counter + 1) as $n
              | .settings.id_counter = $n
              | .settings.items += [$itemTpl | .name = $s.name | .source_uuid = $uuid | .id = $n]
              | .hotkeys += {("libobs.show_scene_item.\($n)"): [], ("libobs.hide_scene_item.\($n)"): []}
            else . end))
  ' "$target" > "$tmp"; then
    run install -m 0600 "$tmp" "$target"
  else
    warnEcho "obs: $target is not valid JSON or cannot take scene $scene, left unpatched"
  fi
  rm -f "$tmp"
}
