# Body of kobo-sync. The Nix wrapper sets host, ssh_key, vault,
# stamp_paths, sync_paths (shell-quoted words for the remote side) and
# transcribe (off, gpu or cpu) before this runs.
# shellcheck disable=SC2154 # set by the wrapper

state=${XDG_STATE_HOME:-$HOME/.local/state}/kobo-sync
library=${XDG_DATA_HOME:-$HOME/.local/share}/kollate/library.db
mkdir -p "$state"

ssh_opts=(
  -i "$ssh_key"
  -o BatchMode=yes
  -o ConnectTimeout=5
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=3
  -o StrictHostKeyChecking=accept-new
  -o "UserKnownHostsFile=$state/known_hosts"
)
# shellcheck disable=SC2029 # remote commands are built here on purpose
on_kobo() { ssh "${ssh_opts[@]}" "root@$host" "$@"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Remote side is BusyBox sh. Missing paths are dropped so tar and
# stat do not fail on a Kobo with no notebooks or markups yet.
# shellcheck disable=SC2016 # expands on the Kobo, not here
existing='for p; do shift; if [ -e "$p" ]; then set -- "$@" "$p"; fi; done'

set +e
listing=$(on_kobo "cd /mnt/onboard && set -- $stamp_paths && $existing && find \"\$@\" -type f -exec stat -c '%n %s %Y' {} +")
rc=$?
set -e
if ((rc == 255)); then
  printf 'event=kobo_unreachable host=%q\n' "$host" >&2
  exit 0
fi
if ((rc != 0)); then
  printf 'event=list_failed host=%q rc=%d\n' "$host" "$rc" >&2
  exit 1
fi

stamp=$(printf '%s' "$listing" | sha256sum | cut -d' ' -f1)
if [[ -z ${KOBO_SYNC_FORCE:-} && -f $state/last-stamp && $(<"$state/last-stamp") == "$stamp" ]]; then
  printf 'event=unchanged\n' >&2
  now >"$state/last-success"
  exit 0
fi

staging=$(mktemp -d "$state/staging.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
on_kobo "cd /mnt/onboard && set -- $sync_paths && $existing && tar -cf - \"\$@\"" \
  | tar -xf - -C "$staging"

db=$staging/.kobo/KoboReader.sqlite
if [[ ! -f $db ]]; then
  printf 'event=no_db path=%q\n' "$db" >&2
  exit 1
fi
# Copied while Nickel may be writing; a torn copy is retried next run.
integrity=$(sqlite3 "$db" 'PRAGMA integrity_check')
if [[ $integrity != ok ]]; then
  printf 'event=integrity_failed result=%q\n' "$integrity" >&2
  exit 1
fi

mirror=$state/mirror
mkdir -p "$mirror"
rsync -a --delete "$staging/" "$mirror/"

kollate-cli --library "$library" import "$mirror"
# Highlights deleted on the Kobo go to Kollate's Trash, which is never exported.
sqlite3 "$library" "INSERT INTO setting (key, value) VALUES ('on_device_delete', 'trash') ON CONFLICT (key) DO UPDATE SET value = excluded.value"

if [[ $transcribe != off ]]; then
  transcribe_args=()
  if [[ $transcribe == cpu ]]; then transcribe_args=(--cpu); fi
  if ! kollate-cli --library "$library" transcribe "${transcribe_args[@]}"; then
    printf 'event=transcribe_failed\n' >&2
  fi
fi
mkdir -p "$vault"
kollate-cli --library "$library" export obsidian "$vault"

printf '%s\n' "$stamp" >"$state/last-stamp"
now >"$state/last-success"
printf 'event=synced vault=%q\n' "$vault" >&2
