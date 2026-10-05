#!/usr/bin/env bash
# Migration verification gate (specs/004-hetzner-encrypted-volumes/contracts/verification.md).
# One result line per check, then a verdict. Exit 0 only for verdict=verified.
# Never prints a secret: the passphrase and the test-account passwords stay in variables.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: verify.sh --volume NAME --checks encryption,compare,health,functional,backup (any of them)
  encryption: --device DEV (the raw block device, not the /dev/mapper one) --mapping NAME
              --pv PV --secret NAMESPACE/NAME --storageclass NAME [--node-exec CMD]
              --storageclass is the class the volume must have been provisioned from: the check reads it
              off the PV and compares it, and compares that class's Secret reference with --secret.
              --node-exec is a command prefix that runs a command on the node holding the volume
              (for example a kubectl debug or ssh wrapper). Without it the checks run on this machine.
  compare:    --kind files    --old-dir DIR --new-dir DIR
              --kind files    --old-manifest FILE --new-manifest FILE
              (manifests are the tab separated path, size, sha256, uid:gid files that migrate-files.sh saves)
              --kind database --namespace NS --old-pod POD --new-pod POD --db NAME[,NAME...]
  health:     --namespace NS --selector LABEL=VALUE [--health-url URL] [--health-seconds N]
  functional: --service matrix|photos|documents|monitoring|notifications|game
              matrix: --homeserver URL (env VERIFY_BOT_TOKEN, an access token for verify-bot, and VERIFY_BOT_ROOM)
              photos: --photos-url URL (env VERIFY_PHOTOS_PASSWORD)
              monitoring: --prometheus-url URL [--alertmanager-url URL] [--grafana-url URL]
              notifications: --ntfy-url URL --ntfy-topic TOPIC
              documents: --couchdb-url URL --couchdb-db DB (env VERIFY_COUCHDB_USER, VERIFY_COUCHDB_PASSWORD)
              game: --namespace NS --selector LABEL=VALUE (reads pod state and logs only)
  backup:     --backup velero|cnpg --backup-namespace NS --backup-for TARGET [--since ISO8601]
              TARGET is the workload namespace for velero, or the cluster name for cnpg
EOF
}

die_usage() {
  echo "verify.sh: $1" >&2
  usage
  exit 2
}

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

volume="" checks=""
device="" mapping="" pv="" secret="" storageclass="" node_exec=""
kind="" old_dir="" new_dir="" old_manifest="" new_manifest="" namespace="" old_pod="" new_pod="" db="" selector=""
health_url="" health_seconds=300
service="" homeserver="" photos_url="" prometheus_url="" alertmanager_url="" grafana_url=""
ntfy_url="" ntfy_topic="" couchdb_url="" couchdb_db=""
backup="" backup_namespace="" backup_for="" since=""

while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die_usage "$1 needs a value"
  case "$1" in
    --volume) volume=$2 ;;
    --checks) checks=$2 ;;
    --device) device=$2 ;;
    --mapping) mapping=$2 ;;
    --pv) pv=$2 ;;
    --secret) secret=$2 ;;
    --storageclass) storageclass=$2 ;;
    --node-exec) node_exec=$2 ;;
    --backup-for) backup_for=$2 ;;
    --kind) kind=$2 ;;
    --old-dir) old_dir=$2 ;;
    --new-dir) new_dir=$2 ;;
    --old-manifest) old_manifest=$2 ;;
    --new-manifest) new_manifest=$2 ;;
    --namespace) namespace=$2 ;;
    --old-pod) old_pod=$2 ;;
    --new-pod) new_pod=$2 ;;
    --db) db=$2 ;;
    --selector) selector=$2 ;;
    --health-url) health_url=$2 ;;
    --health-seconds) health_seconds=$2 ;;
    --service) service=$2 ;;
    --homeserver) homeserver=$2 ;;
    --photos-url) photos_url=$2 ;;
    --prometheus-url) prometheus_url=$2 ;;
    --alertmanager-url) alertmanager_url=$2 ;;
    --grafana-url) grafana_url=$2 ;;
    --ntfy-url) ntfy_url=$2 ;;
    --ntfy-topic) ntfy_topic=$2 ;;
    --couchdb-url) couchdb_url=$2 ;;
    --couchdb-db) couchdb_db=$2 ;;
    --backup) backup=$2 ;;
    --backup-namespace) backup_namespace=$2 ;;
    --since) since=$2 ;;
    *) die_usage "unknown option $1" ;;
  esac
  shift 2
done

[ -n "$volume" ] || die_usage "--volume is required"
[ -n "$checks" ] || die_usage "--checks is required"

failed=0
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# emit CHECK pass|fail DETAIL
emit() {
  printf '%s volume=%s check=%s result=%s detail="%s"\n' "$(ts)" "$volume" "$1" "$2" "${3//\"/\'}"
  [ "$2" = pass ] || failed=1
}

need() {
  [ -n "${!2}" ] || die_usage "$1 needs $3"
}

# Part 0: the volume is really encrypted.
check_encryption() {
  need encryption device --device
  need encryption mapping --mapping
  need encryption secret --secret
  need encryption storageclass --storageclass
  need encryption pv --pv
  local problems=() ns=${secret%%/*} name=${secret#*/} b64 fstype magic head6 ref pvclass nx=()
  [ -z "$node_exec" ] || read -ra nx <<<"$node_exec"

  if ! ref=$(kubectl get storageclass "$storageclass" \
    -o jsonpath='{.parameters.csi\.storage\.k8s\.io/node-publish-secret-namespace}/{.parameters.csi\.storage\.k8s\.io/node-publish-secret-name}' 2>/dev/null); then
    problems+=("cannot read storageclass $storageclass")
  elif [ "$ref" != "$secret" ]; then
    problems+=("storageclass $storageclass references secret '$ref', not $secret")
  fi

  if ! b64=$(kubectl get secret -n "$ns" "$name" -o jsonpath='{.data.encryption-passphrase}' 2>/dev/null); then
    problems+=("secret $secret not found or unreadable")
  elif [ -z "${b64//[[:space:]]/}" ]; then
    problems+=("secret $secret is empty")
  fi

  fstype=$("${nx[@]}" lsblk -no FSTYPE "$device" 2>/dev/null | head -n1 | tr -d '[:space:]') || fstype=""
  [ "$fstype" = crypto_LUKS ] || problems+=("device $device has fstype '${fstype:-none}', want crypto_LUKS")

  "${nx[@]}" cryptsetup status "$mapping" >/dev/null 2>&1 || problems+=("no active crypt mapping $mapping")

  # 53 ef at offset 1080 is the ext4 superblock magic, but a LUKS header (magic "LUKS" BA BE at offset 0)
  # holds random bytes there, which equal 53 ef once in 65536 devices. Only count it without a LUKS header.
  if magic=$("${nx[@]}" dd if="$device" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d '[:space:]') \
    && head6=$("${nx[@]}" dd if="$device" bs=1 count=6 2>/dev/null | od -An -tx1 | tr -d '[:space:]'); then
    if [ "$magic" = 53ef ] && [ "$head6" != 4c554b53babe ]; then
      problems+=("raw device $device shows an ext4 superblock magic at offset 1080")
    fi
  else
    problems+=("cannot read raw device $device")
  fi

  if ! pvclass=$(kubectl get pv "$pv" -o jsonpath='{.spec.storageClassName}' 2>/dev/null); then
    problems+=("cannot read pv $pv")
  elif [ "$pvclass" != "$storageclass" ]; then
    problems+=("pv $pv was provisioned from class '${pvclass:-none}', not $storageclass")
  fi

  if [ ${#problems[@]} -eq 0 ]; then
    emit encryption pass "$fstype on $device, mapping $mapping active, secret $secret set"
  else
    emit encryption fail "$(IFS='; '; echo "${problems[*]}")"
  fi
}

manifest() {
  local dir=$1 p
  (cd "$dir" && find . -type f | LC_ALL=C sort | while IFS= read -r p; do
    printf '%s\t%s\t%s\n' "$p" "$(wc -c <"$p" | tr -d ' ')" "$(sha256sum <"$p" | cut -d' ' -f1)"
  done)
}

table_sql_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/table-checksums.sql"

# differing_keys OLD NEW: first field of every line present in only one file or different.
differing_keys() {
  { diff <(LC_ALL=C sort "$1") <(LC_ALL=C sort "$2") || true; } | sed -n 's/^[<>] //p' | awk -F'\t|[|]' '{print $1}' | LC_ALL=C sort -u | paste -sd, -
}

# compare_database NAME: row counts and checksums of one database on the old and new instance.
compare_database() {
  local name=$1 diffs
  if ! kubectl exec -n "$namespace" "$old_pod" -i -- psql -d "$name" -At -f - <"$table_sql_file" >"$workdir/old.m" 2>"$workdir/err"; then
    emit compare fail "db=$name: query on $namespace/$old_pod failed: $(head -c 200 "$workdir/err")"; return
  fi
  if ! kubectl exec -n "$namespace" "$new_pod" -i -- psql -d "$name" -At -f - <"$table_sql_file" >"$workdir/new.m" 2>"$workdir/err"; then
    emit compare fail "db=$name: query on $namespace/$new_pod failed: $(head -c 200 "$workdir/err")"; return
  fi
  diffs=$(differing_keys "$workdir/old.m" "$workdir/new.m")
  if [ -z "$diffs" ]; then
    emit compare pass "db=$name tables=$(wc -l <"$workdir/old.m" | tr -d ' ')"
  else
    emit compare fail "db=$name tables differ in rows or checksum: $diffs"
  fi
}

# Part 1: data comparison.
check_compare() {
  need compare kind --kind
  local diffs
  case "$kind" in
    files)
      if [ -n "$old_manifest$new_manifest" ]; then
        need compare old_manifest --old-manifest
        need compare new_manifest --new-manifest
        [ -r "$old_manifest" ] && [ -r "$new_manifest" ] || { emit compare fail "cannot read $old_manifest or $new_manifest"; return; }
        LC_ALL=C sort "$old_manifest" >"$workdir/old.m"
        LC_ALL=C sort "$new_manifest" >"$workdir/new.m"
      else
        need compare old_dir --old-dir
        need compare new_dir --new-dir
        [ -d "$old_dir" ] && [ -d "$new_dir" ] || { emit compare fail "cannot read $old_dir or $new_dir"; return; }
        manifest "$old_dir" >"$workdir/old.m"
        manifest "$new_dir" >"$workdir/new.m"
      fi
      diffs=$(differing_keys "$workdir/old.m" "$workdir/new.m")
      if [ -z "$diffs" ]; then
        emit compare pass "files=$(wc -l <"$workdir/old.m" | tr -d ' ') bytes=$(awk -F'\t' '{s+=$2} END {print s+0}' "$workdir/old.m")"
      else
        emit compare fail "differing paths: $diffs"
      fi
      ;;
    database)
      need compare namespace --namespace
      need compare old_pod --old-pod
      need compare new_pod --new-pod
      need compare db --db
      local one_db dbs
      IFS=',' read -ra dbs <<<"$db"
      for one_db in "${dbs[@]}"; do
        compare_database "$one_db"
      done
      ;;
    *) die_usage "--kind must be files or database, got '$kind'" ;;
  esac
}

# Part 2: service health.
check_health() {
  need health namespace --namespace
  need health selector --selector
  local problems=() pods bad probes i interval=${VERIFY_HEALTH_INTERVAL:-10} line logs

  if ! pods=$(kubectl get pods -n "$namespace" -l "$selector" -o json 2>/dev/null); then
    emit health fail "cannot list pods in $namespace with $selector"; return
  fi
  if [ "$(jq '.items | length' <<<"$pods")" -eq 0 ]; then
    problems+=("no pods match $selector in $namespace")
  else
    bad=$(jq -r '.items[] | select(any(.status.containerStatuses[]?; .restartCount > 0)) | "\(.metadata.name) restartCount=\([.status.containerStatuses[].restartCount] | max)"' <<<"$pods" | paste -sd, -)
    [ -z "$bad" ] || problems+=("restarted since the switch: $bad")
    bad=$(jq -r '.items[] | select(all(.status.containerStatuses[]?; .ready) | not) | .metadata.name' <<<"$pods" | paste -sd, -)
    [ -z "$bad" ] || problems+=("not ready: $bad")
  fi

  if [ -n "$health_url" ]; then
    probes=1
    [ "$interval" -gt 0 ] && probes=$(( (health_seconds + interval - 1) / interval ))
    for ((i = 1; i <= probes; i++)); do
      if ! curl -fsS --max-time 10 -o /dev/null "$health_url" 2>/dev/null; then
        problems+=("$health_url failed on probe $i of $probes")
        break
      fi
      [ "$i" -lt "$probes" ] && sleep "$interval"
    done
  fi

  if logs=$(kubectl logs -n "$namespace" -l "$selector" --all-containers --tail=500 --max-log-requests=20 2>&1); then
    problem_re='permission denied|read-only file system|no space left|(error|fatal).*(volume|database|connection refused)'
    # CNPG logs JSON whose keys (error_severity, database_name) trip the grep; judge .record only.
    # 57P03 is a normal replica start. Non-JSON lines keep the plain grep.
    line=$(while IFS= read -r l; do
      if jq -e '.record | type == "object"' <<<"$l" >/dev/null 2>&1; then
        jq -r --arg re "$problem_re" 'select((.record.error_severity | IN("ERROR", "FATAL", "PANIC"))
          and (.record.sql_state_code != "57P03")
          and (.record.message // "" | test($re; "i"))) | .record.message' <<<"$l"
      else
        grep -Ei "$problem_re" <<<"$l" || true
      fi
    done <<<"$logs" | head -n1)
    [ -z "$line" ] || problems+=("logs show: ${line:0:160}")
  else
    problems+=("cannot read logs for $selector in $namespace: ${logs:0:120}")
  fi

  if [ ${#problems[@]} -eq 0 ]; then
    emit health pass "pods ready, no restarts${health_url:+, $health_url answered for ${health_seconds}s}"
  else
    emit health fail "$(IFS='; '; echo "${problems[*]}")"
  fi
}

# Part 3: functional checks, one per service.
functional_matrix() {
  need functional homeserver --homeserver
  local token=${VERIFY_BOT_TOKEN:-} room=${VERIFY_BOT_ROOM:-} txn body auth
  if [ -z "$token" ]; then
    emit functional fail "matrix: VERIFY_BOT_TOKEN is not exported (an access token for verify-bot; password login is not served here)"; return
  fi
  if [ -z "$room" ]; then
    emit functional fail "matrix: VERIFY_BOT_ROOM is not exported (the private test room id)"; return
  fi
  txn=verify-$(date +%s)
  body="verify $txn"
  # The token goes in a mode 600 header file, not on the command line where ps would show it.
  auth="$workdir/auth"
  (umask 077; printf 'Authorization: Bearer %s\n' "$token" >"$auth")
  jq -n --arg b "$body" '{msgtype: "m.text", body: $b}' \
    | curl -fsS --max-time 20 -X PUT -H "@$auth" -H 'Content-Type: application/json' --data @- \
      "$homeserver/_matrix/client/v3/rooms/$room/send/m.room.message/$txn" >/dev/null 2>&1 \
    || { emit functional fail "matrix: send to $room at $homeserver failed"; return; }
  curl -fsS --max-time 20 -H "@$auth" "$homeserver/_matrix/client/v3/rooms/$room/messages?dir=b&limit=10" 2>/dev/null \
    | jq -e --arg b "$body" '[.chunk[]?.content.body] | index($b)' >/dev/null \
    || { emit functional fail "matrix: sent message not read back from $room"; return; }
  emit functional pass "matrix: send and read back in $room"
}

functional_monitoring() {
  need functional prometheus_url --prometheus-url
  curl -fsS --max-time 20 "$prometheus_url/api/v1/query?query=up" 2>/dev/null \
    | jq -e '.status == "success" and (.data.result | length > 0)' >/dev/null \
    || { emit functional fail "monitoring: Prometheus at $prometheus_url did not answer a query"; return; }
  if [ -n "$alertmanager_url" ]; then
    curl -fsS --max-time 20 "$alertmanager_url/api/v2/silences" >/dev/null 2>&1 \
      || { emit functional fail "monitoring: Alertmanager at $alertmanager_url did not list silences"; return; }
  fi
  if [ -n "$grafana_url" ]; then
    curl -fsS --max-time 20 "$grafana_url/api/health" >/dev/null 2>&1 \
      || { emit functional fail "monitoring: Grafana at $grafana_url is not healthy"; return; }
  fi
  emit functional pass "monitoring: Prometheus answered a query"
}

functional_notifications() {
  need functional ntfy_url --ntfy-url
  need functional ntfy_topic --ntfy-topic
  local msg
  msg="verify notifications $(date +%s)-$$"
  curl -fsS --max-time 20 -d "$msg" "$ntfy_url/$ntfy_topic" >/dev/null 2>&1 \
    || { emit functional fail "notifications: post to topic $ntfy_topic at $ntfy_url failed"; return; }
  curl -fsS --max-time 20 "$ntfy_url/$ntfy_topic/json?poll=1&since=all" 2>/dev/null \
    | jq -e --arg m "$msg" 'select(.message == $m)' >/dev/null \
    || { emit functional fail "notifications: posted message not read back from topic $ntfy_topic at $ntfy_url"; return; }
  emit functional pass "notifications: post and poll back on topic $ntfy_topic"
}

functional_documents() {
  need functional couchdb_url --couchdb-url
  need functional couchdb_db --couchdb-db
  local user=${VERIFY_COUCHDB_USER:-} pass=${VERIFY_COUCHDB_PASSWORD:-} id msg cfg="$workdir/couch.cfg" doc rev
  if [ -z "$user" ] || [ -z "$pass" ]; then
    emit functional fail "documents: VERIFY_COUCHDB_USER and VERIFY_COUCHDB_PASSWORD are not both exported (a CouchDB account that may write to $couchdb_db)"; return
  fi
  id="verify-$(date +%s)-$$"
  msg="verify documents $id"
  doc="$couchdb_url/$couchdb_db/$id"
  # The credentials go in a mode 600 curl config, not on the command line where ps would show them.
  (umask 077; printf 'user = "%s:%s"\n' "${user//[\\\"]/\\&}" "${pass//[\\\"]/\\&}" >"$cfg")
  rev=$(jq -n --arg m "$msg" '{message: $m}' \
    | curl -fsS --max-time 20 -K "$cfg" -X PUT -H 'Content-Type: application/json' --data @- "$doc" 2>/dev/null \
    | jq -er '.rev') \
    || { emit functional fail "documents: create of $id in $couchdb_db at $couchdb_url failed"; return; }
  curl -fsS --max-time 20 -K "$cfg" "$doc" 2>/dev/null \
    | jq -e --arg m "$msg" '.message == $m' >/dev/null \
    || { emit functional fail "documents: created document $id not read back from $couchdb_db"; return; }
  curl -fsS --max-time 20 -K "$cfg" -X DELETE "$doc?rev=$rev" 2>/dev/null \
    | jq -e '.ok == true' >/dev/null \
    || { emit functional fail "documents: delete of $id (rev $rev) from $couchdb_db failed"; return; }
  emit functional pass "documents: create, read back and delete in $couchdb_db"
}

functional_game() {
  need functional namespace --namespace
  need functional selector --selector
  local pods logs bad
  if ! pods=$(kubectl get pods -n "$namespace" -l "$selector" -o json 2>/dev/null); then
    emit functional fail "game: cannot list pods in $namespace with $selector"; return
  fi
  if [ "$(jq '.items | length' <<<"$pods")" -eq 0 ]; then
    emit functional fail "game: no pods match $selector in $namespace"; return
  fi
  bad=$(jq -r '.items[] | select(all(.status.containerStatuses[]?; .ready) | not) | .metadata.name' <<<"$pods" | paste -sd, -)
  if [ -n "$bad" ]; then
    emit functional fail "game: not ready: $bad"; return
  fi
  # The whole log, not a tail: the Done line is printed once at startup and scrolls off.
  if ! logs=$(kubectl logs -n "$namespace" -l "$selector" --all-containers --tail=-1 --max-log-requests=20 2>&1); then
    emit functional fail "game: cannot read logs for $selector in $namespace: ${logs:0:120}"; return
  fi
  bad=$(grep -E 'Encountered an unexpected exception|Failed to load' <<<"$logs" | head -n1 || true)
  if [ -n "$bad" ]; then
    emit functional fail "game: logs show: ${bad:0:160}"; return
  fi
  grep -q 'Done (' <<<"$logs" \
    || { emit functional fail "game: no 'Done (' line in the logs of $selector in $namespace, the server did not finish starting"; return; }
  emit functional pass "game: pod ready, log shows Done and no startup errors"
}

check_functional() {
  need functional service --service
  case "$service" in
    matrix) functional_matrix ;;
    monitoring) functional_monitoring ;;
    photos)
      if [ -z "${VERIFY_PHOTOS_PASSWORD:-}" ]; then
        emit functional fail "photos: VERIFY_PHOTOS_PASSWORD is not exported (see README, test accounts)"
      else
        emit functional fail "photos: functional check against ${photos_url:-no --photos-url} not implemented; run it by hand and record it"
      fi
      ;;
    notifications) functional_notifications ;;
    documents) functional_documents ;;
    game) functional_game ;;
    *) die_usage "unknown --service '$service'" ;;
  esac
}

# Part 4: a completed backup of the new volume's data exists.
check_backup() {
  need backup backup --backup
  need backup backup_namespace --backup-namespace
  need backup backup_for --backup-for
  local resource list n
  case "$backup" in
    velero) resource=backups.velero.io ;;
    cnpg) resource=backups.postgresql.cnpg.io ;;
    *) die_usage "--backup must be velero or cnpg, got '$backup'" ;;
  esac
  if ! list=$(kubectl get "$resource" -n "$backup_namespace" -o json 2>/dev/null); then
    emit backup fail "cannot list $resource in $backup_namespace"; return
  fi
  # A completed backup only counts when it belongs to the target: a Velero backup that includes the
  # workload namespace (an empty list means every namespace), or a CNPG backup of the named cluster.
  n=$(jq --arg since "$since" --arg kind "$backup" --arg for "$backup_for" '[.items[]
      | select((.status.phase // "" | ascii_downcase) == "completed")
      | select($since == "" or ((.status.completionTimestamp // .status.stoppedAt // "") >= $since))
      | select(if $kind == "velero"
               then (((.spec.includedNamespaces // []) | (length == 0 or index($for) != null))
                     and (((.spec.excludedNamespaces // []) | index($for)) == null))
               else .spec.cluster.name == $for end)] | length' <<<"$list")
  if [ "$n" -gt 0 ]; then
    emit backup pass "$n completed $backup backup(s) for $backup_for in $backup_namespace${since:+ since $since}"
  else
    emit backup fail "no completed $backup backup for $backup_for in $backup_namespace${since:+ since $since}"
  fi
}

IFS=',' read -ra selected <<<"$checks"
for c in "${selected[@]}"; do
  case "$c" in
    encryption) check_encryption ;;
    compare) check_compare ;;
    health) check_health ;;
    functional) check_functional ;;
    backup) check_backup ;;
    *) die_usage "unknown check '$c'" ;;
  esac
done

if [ "$failed" -eq 0 ]; then
  printf '%s volume=%s verdict=verified\n' "$(ts)" "$volume"
else
  printf '%s volume=%s verdict=failed\n' "$(ts)" "$volume"
  exit 1
fi
