#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#coreutils nixpkgs#curl nixpkgs#gawk nixpkgs#gnused --command bash
# shellcheck shell=bash
# Bump pkgs/claude-desktop to the newest version in Anthropic's official APT
# repo. Version and sha256 come from the repo's Packages index, so nothing is
# downloaded here; fetchurl verifies the .deb against the hash at build time.
#
# Usage: pkgs/claude-desktop/update.sh
set -euo pipefail

nix_file="$(dirname "$(readlink -f "$0")")/default.nix"
index_base="https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main"

# Print "<version> <sha256-hex>" for the highest version in one arch's index.
latest_for_arch() {
  local arch=$1
  curl --fail --silent --show-error --retry 3 "$index_base/binary-$arch/Packages" \
    | awk '/^Version:/ { v = $2 } /^SHA256:/ { print v, $2 }' \
    | sort -V -k1,1 \
    | tail -n 1
}

read -r amd64_version amd64_hex < <(latest_for_arch amd64)
read -r arm64_version arm64_hex < <(latest_for_arch arm64)

if [[ -z $amd64_version || -z $arm64_version ]]; then
  echo "update.sh: could not read a version from the APT index" >&2
  exit 1
fi
if [[ $amd64_version != "$arm64_version" ]]; then
  echo "update.sh: amd64 ($amd64_version) and arm64 ($arm64_version) disagree; not bumping" >&2
  exit 1
fi

current_version=$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$nix_file")
if [[ $current_version == "$amd64_version" ]]; then
  echo "claude-desktop is already at $current_version" >&2
  exit 0
fi

amd64_sri=$(nix hash convert --hash-algo sha256 --to sri "$amd64_hex")
arm64_sri=$(nix hash convert --hash-algo sha256 --to sri "$arm64_hex")

sed -i \
  -e "s|^  version = \".*\";\$|  version = \"$amd64_version\";|" \
  -e "/x86_64-linux = {/,/};/ s|hash = \".*\";|hash = \"$amd64_sri\";|" \
  -e "/aarch64-linux = {/,/};/ s|hash = \".*\";|hash = \"$arm64_sri\";|" \
  "$nix_file"

for expected in "version = \"$amd64_version\"" "$amd64_sri" "$arm64_sri"; do
  if ! grep -qF "$expected" "$nix_file"; then
    echo "update.sh: $nix_file is missing '$expected' after the rewrite" >&2
    exit 1
  fi
done

echo "claude-desktop: $current_version -> $amd64_version" >&2
