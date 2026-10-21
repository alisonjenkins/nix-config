#!/usr/bin/env bash
# tm plan (google): not implemented. No Google Calendar tooling is reachable
# from the agent environment yet; see the design spec.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"

tm_die "the google backend is not implemented; use -b i and import the .ics"
