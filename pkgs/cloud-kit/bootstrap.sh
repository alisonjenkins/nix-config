#!/usr/bin/env bash
# Installs the cloud kit into a Claude cloud session: links skills and agents
# into ~/.claude, adds the user mandates to ~/.claude/CLAUDE.md, and links the
# kit's tools into /usr/local/bin. Run as bin/cloud-kit-bootstrap from the
# kit's store path, normally by the cloud environment's setup script.
# Idempotent: safe to re-run, and a re-run with a newer kit replaces the links.
set -euo pipefail

kit="${CLOUD_KIT:?run this through bin/cloud-kit-bootstrap}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
bin_dir="${CLOUD_KIT_BIN_DIR:-/usr/local/bin}"
# Tools the kit's copy must win for even when the image has one: the image's
# yq is not mikefarah/yq, and the skills call `yq --front-matter=extract`.
prefer_kit=" yq "

log() { printf 'cloud-kit: %s\n' "$*" >&2; }

# Is $1 a link this script made (into any cloud-kit store path)?
ours() { [ -L "$1" ] && [[ "$(readlink "$1")" == /nix/store/*-cloud-kit/* ]]; }

# Link every entry of $1 into $2, replacing our own links but never a file,
# directory or link something else put there. Our links to names the new kit
# no longer ships are removed, so a deleted skill does not linger.
link_entries() {
    local src="$1" dest="$2" entry target
    mkdir -p "$dest"
    for target in "$dest"/*; do
        if ours "$target" && [ ! -e "$src/$(basename "$target")" ]; then
            rm -f "$target"
        fi
    done
    for entry in "$src"/*; do
        [ -e "$entry" ] || continue
        target="$dest/$(basename "$entry")"
        if [ -e "$target" ] || [ -L "$target" ]; then
            if ! ours "$target"; then
                log "kept existing $target"
                continue
            fi
        fi
        ln -sfn "$entry" "$target"
    done
}

link_entries "$kit/skills" "$claude_dir/skills"
link_entries "$kit/agents" "$claude_dir/agents"

# The mandates go in a marked block so a re-run replaces it and whatever else
# the environment wrote to CLAUDE.md stays.
begin='<!-- cloud-kit:begin -->'
end='<!-- cloud-kit:end -->'
md="$claude_dir/CLAUDE.md"
touch "$md"
# Markers are valid when absent, or when there is exactly one of each with the
# end after the begin. Anything else is a half-written or hand-edited block,
# and removing it could take the user's own text with it.
markers="$(awk -v b="$begin" -v e="$end" '
    $0 == b { nb++; lb = NR }
    $0 == e { ne++; le = NR }
    END { print ((nb == 0 && ne == 0) || (nb == 1 && ne == 1 && lb < le)) ? "ok" : "bad" }
' "$md")"
if [ "$markers" != ok ]; then
    log "left $md alone: its cloud-kit markers are unbalanced or out of order"
else
    rest="$(awk -v b="$begin" -v e="$end" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$md")"
    {
        if [ -n "$rest" ]; then printf '%s\n\n' "$rest"; fi
        printf '%s\n' "$begin"
        cat "$kit/CLAUDE.md"
        printf '%s\n' "$end"
    } > "$md.tmp"
    mv "$md.tmp" "$md"
fi
log "linked $(find "$kit/skills" -mindepth 1 -maxdepth 1 | wc -l) skills into $claude_dir"

# Link only tools the image lacks (or ones in prefer_kit): the image's git, gh
# and curl carry the environment's proxy configuration. Links point through
# $kit/tools so they follow the kit they came from.
mkdir -p "$bin_dir"
linked=0
for exe in "$kit"/tools/bin/*; do
    [ -e "$exe" ] || continue
    name="$(basename "$exe")"
    target="$bin_dir/$name"
    if ours "$target"; then
        ln -sfn "$kit/tools/bin/$name" "$target"
        continue
    fi
    if [[ "$prefer_kit" != *" $name "* ]] && command -v "$name" >/dev/null 2>&1; then
        continue
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
        log "kept existing $target"
        continue
    fi
    ln -sfn "$kit/tools/bin/$name" "$target"
    linked=$((linked + 1))
done
log "linked $linked new tools into $bin_dir"
