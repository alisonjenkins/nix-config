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
      # systemd user units have no notify-send on PATH; fall back to libnotify's. Unset
      # on macOS, where osascript is used.
      notify_fallback=''${OBS_NOTIFY_FALLBACK-${if isDarwin then "" else "${pkgs.libnotify}/bin/notify-send"}}
      # Longest gap between repeat notifications while the budget stays exceeded.
      renotify_seconds=86400
      file="$state/guard.json"

      mkdir -p "$state"
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

      now_epoch=$(date -u +%s)
      now_iso=$(date -u -d "@$now_epoch" +%Y-%m-%dT%H:%M:%SZ)

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
          notify_send=$(command -v notify-send || true)
          if [ -z "$notify_send" ] && [ -n "$notify_fallback" ] && [ -x "$notify_fallback" ]; then
            notify_send=$notify_fallback
          fi
          if [ -n "$notify_send" ]; then
            if timeout 5 "$notify_send" "Observability stack over disk budget" "$message" >/dev/null 2>&1; then
              notified=$now_iso
            else
              echo "event=guard_notify_failed notifier=notify-send; retrying on the next run" >&2
            fi
          elif command -v osascript >/dev/null 2>&1; then
            if timeout 5 osascript -e "display notification \"$message\" with title \"Observability stack over disk budget\"" >/dev/null 2>&1; then
              notified=$now_iso
            else
              echo "event=guard_notify_failed notifier=osascript; retrying on the next run" >&2
            fi
          else
            echo "event=guard_notify_skipped reason=no_notifier" >&2
          fi
        fi
      else
        if [ "$previous" = over ]; then
          echo "event=guard_back_under_budget used_bytes=$used cap_bytes=$cap" >&2
        fi
        notified=""
      fi

      tmp=$(mktemp "$state/guard.json.XXXXXX")
      trap 'rm -f "$tmp"' EXIT
      jq -n --arg state "$current" --argjson used "$used" --argjson cap "$cap" --arg updated "$now_iso" --arg notified "$notified" \
        '{state: $state, usedBytes: $used, capBytes: $cap, updated: $updated} + (if $notified == "" then {} else {notified: $notified} end)' > "$tmp"
      mv "$tmp" "$file"

      if [ -n "$metrics_url" ]; then
        over=0
        if [ "$current" = over ]; then over=1; fi
        now="''${now_epoch}000000000"
        curl -fsS --max-time 3 -X POST -H 'Content-Type: application/json' "$metrics_url" --data "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"observability-stack-guard\"}}]},\"scopeMetrics\":[{\"metrics\":[
          {\"name\":\"observability.guard.used_bytes\",\"gauge\":{\"dataPoints\":[{\"asInt\":\"$used\",\"timeUnixNano\":\"$now\"}]}},
          {\"name\":\"observability.guard.cap_bytes\",\"gauge\":{\"dataPoints\":[{\"asInt\":\"$cap\",\"timeUnixNano\":\"$now\"}]}},
          {\"name\":\"observability.guard.over_budget\",\"gauge\":{\"dataPoints\":[{\"asInt\":\"$over\",\"timeUnixNano\":\"$now\"}]}}
        ]}]}]}" >/dev/null || echo "observability-stack-guard: could not push guard metrics to $metrics_url (is Prometheus up?)" >&2
      fi
    '';
  };
in
{
  inherit run guard machineScript;
}
