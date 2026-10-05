#!/usr/bin/env bash
# Fails if a Nix file under pkgs/ carries a zero-padded CurseForge CDN path.
# The CDN path splits the file ID as <id / 1000>/<id % 1000> with no padding
# (7956082 is files/7956/82/). A padded form such as files/7956/082/ is answered
# with a 403 by CloudFront (a missing S3 key), so the jar can never be fetched
# in CI; builds only pass where the jar already sits in a /nix/store.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if hits="$(grep -rnE 'forgecdn\.net/files/[0-9]+/0[0-9]+/' --include='*.nix' "${root}/pkgs")"; then
    echo "FAIL zero-padded CurseForge CDN path (use files/<id/1000>/<id%1000>, no leading zero):" >&2
    echo "${hits}" >&2
    exit 1
fi
