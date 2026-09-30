{ pkgs }:
let
  jsoncParser = pkgs.fetchzip {
    url = "https://registry.npmjs.org/jsonc-parser/-/jsonc-parser-3.3.1.tgz";
    hash = "sha256-eZb4Epz0UsTTaSstqBl46Sy/KRyKaJ+vBUJ92/6wsZY=";
  };

  # Deep-merges `patch` into the JSONC file at `path`, creating the file if it
  # doesn't exist yet. Keys the patch doesn't mention — auth tokens, state the
  # CLI writes on its own — and the user's comments pass through untouched.
  # Avoids `home.file`'s symlink-into-the-store approach: that would make the
  # file read-only, which breaks the CLI's own writes to it.
  jsonMerge = pkgs.writeShellScript "copilot-cli-json-merge" ''
    exec ${pkgs.nodejs}/bin/node ${pkgs.replaceVars ./merge-jsonc.js { inherit jsoncParser; }} "$@"
  '';
in
rec {
  inherit jsonMerge;

  # Grants a project (identified by its absolute path in permissions-config.json's
  # `locations`) extra trusted directories and/or pre-approved command patterns,
  # without disturbing anything else already recorded for that project or any
  # other. Directories are unioned/deduped; command patterns are merged into
  # one `{kind: "commands"}` tool_approvals entry (also unioned/deduped),
  # collapsing any existing commands entries into it without losing their
  # identifiers.
  #
  # Args: <perm-file> <project-path> <dir>... -- <command-pattern>...
  # (the "--" separator is required even when one side is empty)
  trustProject = pkgs.writeShellScript "copilot-cli-trust-project" ''
    set -euo pipefail
    perm_file="$1"; proj="$2"; shift 2

    dirs=()
    cmds=()
    side=dirs
    for a in "$@"; do
      if [ "$a" = "--" ]; then side=cmds; continue; fi
      if [ "$side" = dirs ]; then dirs+=("$a"); else cmds+=("$a"); fi
    done

    skip() { echo "copilot-cli: not updating $perm_file: $1" >&2; exit 0; }

    mkdir -p "$(dirname "$perm_file")" || skip "cannot create its directory"
    [ -s "$perm_file" ] || echo '{}' > "$perm_file" || skip "cannot write it"

    dirs_json="$(printf '%s\n' "''${dirs[@]:-}" | sed '/^$/d' | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)"
    cmds_json="$(printf '%s\n' "''${cmds[@]:-}" | sed '/^$/d' | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)"

    tmp="$(mktemp "$perm_file.XXXXXX")" || skip "cannot create a temp file next to it"
    trap 'rm -f "$tmp"' EXIT
    ${pkgs.jq}/bin/jq --arg proj "$proj" --argjson dirs "$dirs_json" --argjson cmds "$cmds_json" '
      (.locations[$proj].allowed_directories // []) as $existingDirs
      | .locations[$proj].allowed_directories = (($existingDirs + $dirs) | unique)
      | (.locations[$proj].tool_approvals // []) as $approvals
      | ($approvals | map(select(.kind == "commands") | .commandIdentifiers // []) | add // []) as $existingCmds
      | (($existingCmds + $cmds) | unique) as $mergedCmds
      | if ($cmds | length) > 0 then
          .locations[$proj].tool_approvals =
            ([{kind: "commands", commandIdentifiers: $mergedCmds}]
             + ($approvals | map(select(.kind != "commands"))))
        else . end
    ' "$perm_file" > "$tmp" || skip "it is not valid JSON"
    mv "$tmp" "$perm_file" || skip "cannot replace it"
  '';

  # Grants every git repo directly under each parent (from the optional
  # parents file and from discovery under <discover-root>) the given access.
  # Args: <perm-file> <parents-file> <discover-root> <dir>... -- <command-pattern>...
  trustParents = pkgs.writeShellScript "copilot-cli-trust-parents" ''
    set -euo pipefail
    perm_file="$1"; parents_file="$2"; discover_root="$3"; shift 3

    parents=()

    if [ -f "$parents_file" ]; then
      while IFS= read -r parent || [ -n "$parent" ]; do
        [ -z "$parent" ] && continue
        parent="''${parent/#\~/$HOME}"
        parents+=("''${parent%/}")
      done < "$parents_file"
    fi

    if [ -n "$discover_root" ] && [ -d "$discover_root" ]; then
      for group in "$discover_root"/*/; do
        [ -d "$group" ] || continue
        [ -e "$group.git" ] && continue
        for child in "$group"*/; do
          if [ -e "$child.git" ]; then
            parents+=("''${group%/}")
            break
          fi
        done
      done
    fi

    [ "''${#parents[@]}" -gt 0 ] || exit 0

    if [ -f "$perm_file" ] && ! ${pkgs.jq}/bin/jq empty "$perm_file" 2>/dev/null; then
      echo "copilot-cli: not updating $perm_file: it is not valid JSON" >&2
      exit 0
    fi

    printf '%s\n' "''${parents[@]}" | sort -u | while IFS= read -r parent; do
      [ -d "$parent" ] || continue
      for proj in "$parent"/*/; do
        [ -e "$proj.git" ] || continue
        ${trustProject} "$perm_file" "''${proj%/}" "$@"
      done
    done
  '';
}
