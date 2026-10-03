#!/usr/bin/env bash
# Migration verification gate (specs/004-hetzner-encrypted-volumes/contracts/verification.md).
# One result line per check, then a verdict. Exit 0 only for verdict=verified.
# Never prints a secret: the passphrase and the test-account passwords stay in variables.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: verify.sh --volume NAME [--checks encryption,compare,health,functional,backup]
  encryption: --device DEV --mapping NAME --secret NAMESPACE/NAME
  compare:    --kind files    --old-dir DIR --new-dir DIR
              --kind database --namespace NS --old-pod POD --new-pod POD --db NAME
  health:     --namespace NS --selector LABEL=VALUE [--health-url URL] [--health-seconds N]
  functional: --service matrix|photos|documents|monitoring|notifications|game
              matrix: --homeserver URL (env VERIFY_BOT_PASSWORD, VERIFY_BOT_ROOM, optional VERIFY_BOT_USER)
              photos: --photos-url URL (env VERIFY_PHOTOS_PASSWORD)
              monitoring: --prometheus-url URL [--alertmanager-url URL] [--grafana-url URL]
  backup:     --backup velero|cnpg --backup-namespace NS [--since ISO8601]
EOF
}

die_usage() {
  echo "verify.sh: $1" >&2
  usage
  exit 2
}

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

volume="" checks="encryption,compare,health,functional,backup"
device="" mapping="" secret=""
kind="" old_dir="" new_dir="" namespace="" old_pod="" new_pod="" db="" selector=""
health_url="" health_seconds=300
service="" homeserver="" photos_url="" prometheus_url="" alertmanager_url="" grafana_url=""
backup="" backup_namespace="" since=""

while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die_usage "$1 needs a value"
  case "$1" in
    --volume) volume=$2 ;;
    --checks) checks=$2 ;;
    --device) device=$2 ;;
    --mapping) mapping=$2 ;;
    --secret) secret=$2 ;;
    --kind) kind=$2 ;;
    --old-dir) old_dir=$2 ;;
    --new-dir) new_dir=$2 ;;
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
    --backup) backup=$2 ;;
    --backup-namespace) backup_namespace=$2 ;;
    --since) since=$2 ;;
    *) die_usage "unknown option $1" ;;
  esac
  shift 2
done

[ -n "$volume" ] || die_usage "--volume is required"

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
  local problems=() ns=${secret%%/*} name=${secret#*/} b64 fstype magic

  if ! b64=$(kubectl get secret -n "$ns" "$name" -o jsonpath='{.data.encryption-passphrase}' 2>/dev/null); then
    problems+=("secret $secret not found or unreadable")
  elif [ -z "${b64//[[:space:]]/}" ]; then
    problems+=("secret $secret is empty")
  fi

  fstype=$(lsblk -no FSTYPE "$device" 2>/dev/null | head -n1 | tr -d '[:space:]') || fstype=""
  [ "$fstype" = crypto_LUKS ] || problems+=("device $device has fstype '${fstype:-none}', want crypto_LUKS")

  cryptsetup status "$mapping" >/dev/null 2>&1 || problems+=("no active crypt mapping $mapping")

  if magic=$(dd if="$device" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d '[:space:]'); then
    [ "$magic" != 53ef ] || problems+=("raw device $device shows an ext4 superblock magic at offset 1080")
  else
    problems+=("cannot read raw device $device")
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

# One line per table: schema.table|row count|md5 of the table's rows.
read -r -d '' table_sql <<'SQL' || true
SELECT t.table_schema || '.' || t.table_name || '|' ||
  (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', t.table_schema, t.table_name), false, true, '')))[1]::text || '|' ||
  (xpath('/row/h/text()', query_to_xml(format('select coalesce(md5(string_agg(x::text, '','' order by x::text)), '''') as h from %I.%I x', t.table_schema, t.table_name), false, true, '')))[1]::text
FROM information_schema.tables t
WHERE t.table_type = 'BASE TABLE' AND t.table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY 1
SQL

# differing_keys OLD NEW: first field of every line present in only one file or different.
differing_keys() {
  { diff <(LC_ALL=C sort "$1") <(LC_ALL=C sort "$2") || true; } | sed -n 's/^[<>] //p' | awk -F'\t|[|]' '{print $1}' | LC_ALL=C sort -u | paste -sd, -
}

# Part 1: data comparison.
check_compare() {
  need compare kind --kind
  local diffs
  case "$kind" in
    files)
      need compare old_dir --old-dir
      need compare new_dir --new-dir
      [ -d "$old_dir" ] && [ -d "$new_dir" ] || { emit compare fail "cannot read $old_dir or $new_dir"; return; }
      manifest "$old_dir" >"$workdir/old.m"
      manifest "$new_dir" >"$workdir/new.m"
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
      if ! kubectl exec -n "$namespace" "$old_pod" -- psql -d "$db" -At -c "$table_sql" >"$workdir/old.m" 2>"$workdir/err"; then
        emit compare fail "query on $namespace/$old_pod db=$db failed: $(head -c 200 "$workdir/err")"; return
      fi
      if ! kubectl exec -n "$namespace" "$new_pod" -- psql -d "$db" -At -c "$table_sql" >"$workdir/new.m" 2>"$workdir/err"; then
        emit compare fail "query on $namespace/$new_pod db=$db failed: $(head -c 200 "$workdir/err")"; return
      fi
      diffs=$(differing_keys "$workdir/old.m" "$workdir/new.m")
      if [ -z "$diffs" ]; then
        emit compare pass "tables=$(wc -l <"$workdir/old.m" | tr -d ' ') db=$db"
      else
        emit compare fail "tables differ in rows or checksum: $diffs"
      fi
      ;;
    *) die_usage "--kind must be files or database, got '$kind'" ;;
  esac
}

# Part 2: service health.
check_health() {
  need health namespace --namespace
  need health selector --selector
  local problems=() pods bad probes i interval=${VERIFY_HEALTH_INTERVAL:-10} line

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

  line=$(kubectl logs -n "$namespace" -l "$selector" --all-containers --tail=500 2>/dev/null \
    | grep -Ei 'permission denied|read-only file system|no space left|(error|fatal).*(volume|database|connection refused)' | head -n1 || true)
  [ -z "$line" ] || problems+=("logs show: ${line:0:160}")

  if [ ${#problems[@]} -eq 0 ]; then
    emit health pass "pods ready, no restarts${health_url:+, $health_url answered for ${health_seconds}s}"
  else
    emit health fail "$(IFS='; '; echo "${problems[*]}")"
  fi
}

# Part 3: functional checks, one per service.
functional_matrix() {
  need functional homeserver --homeserver
  local user=${VERIFY_BOT_USER:-verify-bot} token login txn
  txn=verify-$(date +%s)
  if [ -z "${VERIFY_BOT_PASSWORD:-}" ]; then
    emit functional fail "matrix: VERIFY_BOT_PASSWORD is not exported (see README, test accounts)"; return
  fi
  login=$(jq -n --arg u "$user" --arg p "$VERIFY_BOT_PASSWORD" \
    '{type: "m.login.password", identifier: {type: "m.id.user", user: $u}, password: $p}' \
    | curl -fsS --max-time 20 -X POST -H 'Content-Type: application/json' --data @- "$homeserver/_matrix/client/v3/login" 2>/dev/null) \
    || { emit functional fail "matrix: login at $homeserver failed for $user"; return; }
  token=$(jq -r '.access_token // empty' <<<"$login")
  [ -n "$token" ] || { emit functional fail "matrix: login at $homeserver returned no access token"; return; }
  if [ -z "${VERIFY_BOT_ROOM:-}" ]; then
    emit functional fail "matrix: VERIFY_BOT_ROOM is not exported (the private test room id)"; return
  fi
  local body="verify $txn" room=${VERIFY_BOT_ROOM}
  jq -n --arg b "$body" '{msgtype: "m.text", body: $b}' \
    | curl -fsS --max-time 20 -X PUT -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data @- \
      "$homeserver/_matrix/client/v3/rooms/$room/send/m.room.message/$txn" >/dev/null 2>&1 \
    || { emit functional fail "matrix: send to $room at $homeserver failed"; return; }
  curl -fsS --max-time 20 -H "Authorization: Bearer $token" "$homeserver/_matrix/client/v3/rooms/$room/messages?dir=b&limit=10" 2>/dev/null \
    | jq -e --arg b "$body" '[.chunk[]?.content.body] | index($b)' >/dev/null \
    || { emit functional fail "matrix: sent message not read back from $room"; return; }
  emit functional pass "matrix: login, send and read back in $room"
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
    documents | notifications | game)
      emit functional fail "$service: functional check not implemented; run it by hand and record it"
      ;;
    *) die_usage "unknown --service '$service'" ;;
  esac
}

# Part 4: a completed backup of the new volume's data exists.
check_backup() {
  need backup backup --backup
  need backup backup_namespace --backup-namespace
  local resource list n
  case "$backup" in
    velero) resource=backups.velero.io ;;
    cnpg) resource=backups.postgresql.cnpg.io ;;
    *) die_usage "--backup must be velero or cnpg, got '$backup'" ;;
  esac
  if ! list=$(kubectl get "$resource" -n "$backup_namespace" -o json 2>/dev/null); then
    emit backup fail "cannot list $resource in $backup_namespace"; return
  fi
  n=$(jq --arg since "$since" '[.items[]
      | select((.status.phase // "" | ascii_downcase) == "completed")
      | select($since == "" or ((.status.completionTimestamp // .status.stoppedAt // "") >= $since))] | length' <<<"$list")
  if [ "$n" -gt 0 ]; then
    emit backup pass "$n completed $backup backup(s) in $backup_namespace${since:+ since $since}"
  else
    emit backup fail "no completed $backup backup in $backup_namespace${since:+ since $since}"
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
