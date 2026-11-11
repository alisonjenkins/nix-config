# The two scripts the supervisors run: the stack itself, and the disk guard.
{ lib, pkgs, cfg, dataDir, stateDir, pod, configs, collector, grafana, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  configFarm = pkgs.linkFarm "observability-stack-config" (configs.files // collector.files // grafana.files);

  published = {
    grafana = cfg.ports.grafana;
    loki = cfg.ports.loki;
    tempo = cfg.ports.tempo;
    prometheus = cfg.ports.prometheus;
    otlpGrpc = cfg.ports.otlpGrpc;
    otlpHttp = cfg.ports.otlpHttp;
  };

  # podman runs containers inside a VM on macOS. The stack gets its own named machine, so
  # it never resizes one used by other tools; sizing applies only at init. podman allows one
  # running machine, so another running machine stops the start with a message.
  # CONTAINER_CONNECTION points every later podman call in the script at that machine.
  machineScript = { isDarwin, machine }: lib.optionalString isDarwin ''
    machine=${lib.escapeShellArg machine.name}
    if ! podman machine inspect "$machine" >/dev/null 2>&1; then
      podman machine init --cpus ${toString machine.cpus} --memory ${toString machine.memoryMiB} --disk-size ${toString machine.diskSizeGiB} "$machine"
    fi
    if [ "$(podman machine inspect --format '{{.State}}' "$machine" 2>/dev/null)" != running ]; then
      while read -r name running; do
        name=''${name%\*}
        if [ "$running" = true ] && [ "$name" != "$machine" ]; then
          echo "observability-stack: podman machine '$name' is running; podman runs one machine at a time on macOS. Stop it (podman machine stop $name) or point modules.observabilityStack.podmanMachine.name at it." >&2
          exit 1
        fi
      done < <(podman machine list --format '{{.Name}} {{.Running}}' 2>/dev/null || true)
      podman machine start "$machine"
    fi
    export CONTAINER_CONNECTION="$machine"
  '';
  ensureMachine = machineScript { inherit isDarwin; machine = cfg.podmanMachine; };

  capBytes = cfg.maxDiskGB * 1024 * 1024 * 1024;

  run = pkgs.writeShellApplication {
    name = "observability-stack-run";
    runtimeInputs = [ pkgs.coreutils ] ++ lib.optional isDarwin cfg.podmanPackage;
    text = ''
      data=''${OBS_DATA_DIR:-${lib.escapeShellArg dataDir}}
      pod=observability

      # Stopping the supervisor (disable, logout, reboot) must not leave containers behind.
      # shellcheck disable=SC2329 # runs through the EXIT trap
      cleanup() { podman pod rm -f "$pod" >/dev/null 2>&1 || true; }
      trap cleanup EXIT
      trap 'exit 143' TERM INT

      if ! command -v podman >/dev/null 2>&1; then
        echo "observability-stack: podman not found on PATH. On NixOS set modules.podman.enable = true; elsewhere install podman." >&2
        exit 1
      fi
      ${ensureMachine}
      mkdir -p "$data/loki" "$data/tempo" "$data/prometheus" "$data/grafana"
      rm -rf "$data/config"
      mkdir -p "$data/config"
      cp -rL --no-preserve=mode,ownership ${configFarm}/. "$data/config/"
      chmod -R u+rwX,go+rX "$data/config"

      # Drop a previous run first, so its own listeners are not mistaken for a clash.
      podman pod rm -f "$pod" >/dev/null 2>&1 || true

      ${lib.concatStrings (lib.mapAttrsToList (option: port: ''
        if (exec 3<>/dev/tcp/127.0.0.1/${toString port}) 2>/dev/null; then
          echo "observability-stack: port ${toString port} is already in use on this machine. Stop the program using it, or change modules.observabilityStack.ports.${option}." >&2
          exit 1
        fi
      '') published)}
      podman kube play --replace ${pod.yamlFile}

      # Background sleep + wait so a TERM from the supervisor is handled at once.
      while state=$(podman pod inspect "$pod" --format '{{.State}}' 2>/dev/null) && { [ "$state" = Running ] || [ "$state" = Degraded ]; }; do
        sleep 10 &
        wait $!
      done
      echo "observability-stack: pod state is '$state'; exiting so the supervisor restarts it" >&2
      exit 1
    '';
  };

  guard = pkgs.writeShellApplication {
    name = "observability-stack-guard";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq ];
    text = ''
      data=''${OBS_DATA_DIR:-${lib.escapeShellArg dataDir}}
      cap=''${OBS_CAP_BYTES:-${toString capBytes}}
      state=''${OBS_STATE_DIR:-${lib.escapeShellArg stateDir}}
      metrics_url=''${OBS_METRICS_URL-http://127.0.0.1:${toString cfg.ports.prometheus}/api/v1/otlp/v1/metrics}
      prometheus_ready_url=''${OBS_PROMETHEUS_READY_URL-http://127.0.0.1:${toString cfg.ports.prometheus}/-/ready}
      loki_ready_url=''${OBS_LOKI_READY_URL-http://127.0.0.1:${toString cfg.ports.loki}/ready}
      tempo_ready_url=''${OBS_TEMPO_READY_URL-http://127.0.0.1:${toString cfg.ports.tempo}/ready}
      # systemd user units have no notify-send on PATH; fall back to libnotify's. Unset
      # on macOS, where osascript is used.
      notify_fallback=''${OBS_NOTIFY_FALLBACK-${if isDarwin then "" else "${pkgs.libnotify}/bin/notify-send"}}
      # Longest gap between repeat notifications while a bad state persists (both checks below).
      renotify_seconds=86400
      # A store readiness check must fail for this long before it notifies, so one slow
      # poll around a restart (this runs every 5 minutes) doesn't fire.
      stack_sustained_seconds=600
      file="$state/guard.json"
      health_file="$state/stack-health.json"
      now_epoch=$(date -u +%s)
      now_iso=$(date -u -d "@$now_epoch" +%Y-%m-%dT%H:%M:%SZ)

      notify_send=$(command -v notify-send || true)
      if [ -z "$notify_send" ] && [ -n "$notify_fallback" ] && [ -x "$notify_fallback" ]; then
        notify_send=$notify_fallback
      fi

      # Prints nothing; returns 0 once a notifier accepted the message, 1 otherwise (including
      # "no notifier"), so the caller only records $notified on success and retries next run.
      send_notification() {
        local title=$1 message=$2
        if [ -n "$notify_send" ]; then
          if timeout 5 "$notify_send" "$title" "$message" >/dev/null 2>&1; then
            return 0
          fi
          echo "event=guard_notify_failed notifier=notify-send; retrying on the next run" >&2
          return 1
        elif command -v osascript >/dev/null 2>&1; then
          if timeout 5 osascript -e "display notification \"$message\" with title \"$title\"" >/dev/null 2>&1; then
            return 0
          fi
          echo "event=guard_notify_failed notifier=osascript; retrying on the next run" >&2
          return 1
        else
          echo "event=guard_notify_skipped reason=no_notifier" >&2
          return 1
        fi
      }

      mkdir -p "$state"
      tmp=""
      htmp=""
      trap 'rm -f "$tmp" "$htmp"' EXIT
      used=0
      for store in loki tempo prometheus; do
        if [ -d "$data/$store" ]; then
          # Files vanish mid-walk (compaction, WAL rotation): du exits 1 but still prints a total.
          kib=$({ du -sk "$data/$store" 2>/dev/null || true; } | cut -f1)
          used=$((used + ''${kib:-0} * 1024))
        fi
      done

      previous=ok
      notified=""
      if [ -f "$file" ]; then
        if ! read -r previous notified < <(jq -r '[.state, (.notified // "")] | join(" ")' "$file" 2>/dev/null); then
          echo "event=guard_state_unreadable file=$file; treating the previous state as ok" >&2
          previous=ok
          notified=""
        fi
      fi
      if [ "$previous" != over ]; then previous=ok; fi

      low=$((cap * 9 / 10))
      if [ "$used" -ge "$cap" ] || { [ "$previous" = over ] && [ "$used" -ge "$low" ]; }; then
        current=over
      else
        current=ok
      fi

      if [ "$current" = over ]; then
        notify=0
        if [ "$previous" != over ] || [ -z "$notified" ]; then
          notify=1
        else
          last=$(date -u -d "$notified" +%s 2>/dev/null) || last=0
          if [ $((now_epoch - last)) -ge "$renotify_seconds" ]; then notify=1; fi
        fi
        if [ "$notify" = 1 ]; then
          message="The observability stack uses $((used / 1048576)) MiB of its $((cap / 1048576)) MiB disk budget. Ingestion continues."
          echo "event=guard_over_budget used_bytes=$used cap_bytes=$cap previous=$previous" >&2
          if send_notification "Observability stack over disk budget" "$message"; then
            notified=$now_iso
          fi
        fi
      else
        if [ "$previous" = over ]; then
          echo "event=guard_back_under_budget used_bytes=$used cap_bytes=$cap" >&2
        fi
        notified=""
      fi

      tmp=$(mktemp "$state/guard.json.XXXXXX")
      jq -n --arg state "$current" --argjson used "$used" --argjson cap "$cap" --arg updated "$now_iso" --arg notified "$notified" \
        '{state: $state, usedBytes: $used, capBytes: $cap, updated: $updated} + (if $notified == "" then {} else {notified: $notified} end)' > "$tmp"
      mv "$tmp" "$file"

      # Causal order: whichever store answers /ready first names the one responsible.
      cause=""
      if ! curl -fsS --max-time 3 "$prometheus_ready_url" >/dev/null 2>&1; then
        cause="prometheus readiness check failed"
      elif ! curl -fsS --max-time 3 "$loki_ready_url" >/dev/null 2>&1; then
        cause="loki readiness check failed"
      elif ! curl -fsS --max-time 3 "$tempo_ready_url" >/dev/null 2>&1; then
        cause="tempo readiness check failed"
      fi

      h_previous=ok
      h_bad_since=""
      h_notified=""
      if [ -f "$health_file" ]; then
        if ! read -r h_previous h_bad_since h_notified < <(jq -r '[.state, (.badSince // ""), (.notified // "")] | join(" ")' "$health_file" 2>/dev/null); then
          echo "event=guard_health_state_unreadable file=$health_file; treating the previous state as ok" >&2
          h_previous=ok
          h_bad_since=""
          h_notified=""
        fi
      fi
      if [ "$h_previous" != down ]; then h_previous=ok; fi

      if [ -n "$cause" ]; then
        h_current=down
        if [ -z "$h_bad_since" ]; then h_bad_since=$now_iso; fi
        bad_since_epoch=$(date -u -d "$h_bad_since" +%s 2>/dev/null) || bad_since_epoch=$now_epoch
        sustained=$((now_epoch - bad_since_epoch))
        notify=0
        if [ "$sustained" -ge "$stack_sustained_seconds" ]; then
          if [ "$h_previous" != down ] || [ -z "$h_notified" ]; then
            notify=1
          else
            last=$(date -u -d "$h_notified" +%s 2>/dev/null) || last=0
            if [ $((now_epoch - last)) -ge "$renotify_seconds" ]; then notify=1; fi
          fi
        fi
        if [ "$notify" = 1 ]; then
          message="$cause, since $h_bad_since. Claude Code token metrics are not being recorded until this is fixed; check with cc-obs-query health."
          printf 'event=guard_stack_down cause=%q bad_since=%q\n' "$cause" "$h_bad_since" >&2
          if send_notification "Observability stack telemetry is down" "$message"; then
            h_notified=$now_iso
          fi
        fi
      else
        if [ "$h_previous" = down ]; then
          echo "event=guard_stack_recovered bad_since=$h_bad_since" >&2
        fi
        h_current=ok
        h_bad_since=""
        h_notified=""
      fi

      htmp=$(mktemp "$state/stack-health.json.XXXXXX")
      jq -n --arg state "$h_current" --arg badSince "$h_bad_since" --arg notified "$h_notified" \
        '{state: $state} + (if $badSince == "" then {} else {badSince: $badSince} end) + (if $notified == "" then {} else {notified: $notified} end)' > "$htmp"
      mv "$htmp" "$health_file"

      if [ -n "$metrics_url" ]; then
        over=0
        if [ "$current" = over ]; then over=1; fi
        down=0
        if [ "$h_current" = down ]; then down=1; fi
        now="''${now_epoch}000000000"
        curl -fsS --max-time 3 -X POST -H 'Content-Type: application/json' "$metrics_url" --data "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"observability-stack-guard\"}}]},\"scopeMetrics\":[{\"metrics\":[
          {\"name\":\"observability.guard.used_bytes\",\"gauge\":{\"dataPoints\":[{\"asInt\":\"$used\",\"timeUnixNano\":\"$now\"}]}},
          {\"name\":\"observability.guard.cap_bytes\",\"gauge\":{\"dataPoints\":[{\"asInt\":\"$cap\",\"timeUnixNano\":\"$now\"}]}},
          {\"name\":\"observability.guard.over_budget\",\"gauge\":{\"dataPoints\":[{\"asInt\":\"$over\",\"timeUnixNano\":\"$now\"}]}},
          {\"name\":\"observability.guard.stack_down\",\"gauge\":{\"dataPoints\":[{\"asInt\":\"$down\",\"timeUnixNano\":\"$now\"}]}}
        ]}]}]}" >/dev/null || echo "observability-stack-guard: could not push guard metrics to $metrics_url (is Prometheus up?)" >&2
      fi
    '';
  };
in
{
  inherit run guard machineScript;
}
