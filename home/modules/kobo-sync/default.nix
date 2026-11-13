{ config, lib, pkgs, ... }:
let
  cfg = config.modules.koboSync;

  # Paths under /mnt/onboard that kollate-cli reads; anything else on the
  # Kobo is skipped so a sync stays small over Wi-Fi.
  syncPaths = [
    ".kobo/KoboReader.sqlite"
    ".kobo/KoboReader.sqlite-wal"
    ".kobo/KoboReader.sqlite-journal"
    ".kobo/version"
    ".kobo/markups"
    ".kobo-images"
    "My Notebooks"
  ];
  # Cheap to list on every poll; covers are left out because they only
  # change when the files above do.
  stampPaths = lib.filter (p: p != ".kobo-images") syncPaths;

  remoteQuote = paths: lib.concatMapStringsSep " " lib.escapeShellArg paths;

  koboSync = pkgs.writeShellApplication {
    name = "kobo-sync";
    runtimeInputs = with pkgs; [ coreutils openssh gnutar rsync sqlite kollate-cli ];
    text = ''
      state=''${XDG_STATE_HOME:-$HOME/.local/state}/kobo-sync
      library=''${XDG_DATA_HOME:-$HOME/.local/share}/kollate/library.db
      host=${lib.escapeShellArg cfg.host}
      vault=${lib.escapeShellArg cfg.exportFolder}
      mkdir -p "$state"

      ssh_opts=(
        -i ${lib.escapeShellArg cfg.sshKey}
        -o BatchMode=yes
        -o ConnectTimeout=5
        -o ServerAliveInterval=5
        -o ServerAliveCountMax=3
        -o StrictHostKeyChecking=accept-new
        -o "UserKnownHostsFile=$state/known_hosts"
      )
      # shellcheck disable=SC2029 # remote commands are built here on purpose
      on_kobo() { ssh "''${ssh_opts[@]}" "root@$host" "$@"; }
      now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

      # Remote side is BusyBox sh. Missing paths are dropped so tar and
      # stat do not fail on a Kobo with no notebooks or markups yet.
      # shellcheck disable=SC2016 # expands on the Kobo, not here
      existing='for p; do shift; if [ -e "$p" ]; then set -- "$@" "$p"; fi; done'

      set +e
      listing=$(on_kobo "cd /mnt/onboard && set -- ${remoteQuote stampPaths} && $existing && find \"\$@\" -type f -exec stat -c '%n %s %Y' {} +")
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
      if [[ -z ''${KOBO_SYNC_FORCE:-} && -f $state/last-stamp && $(<"$state/last-stamp") == "$stamp" ]]; then
        printf 'event=unchanged\n' >&2
        now >"$state/last-success"
        exit 0
      fi

      staging=$(mktemp -d "$state/staging.XXXXXX")
      trap 'rm -rf -- "$staging"' EXIT
      on_kobo "cd /mnt/onboard && set -- ${remoteQuote syncPaths} && $existing && tar -cf - \"\$@\"" \
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

      ${lib.optionalString cfg.transcribe.enable ''
        if ! kollate-cli --library "$library" transcribe ${lib.optionalString cfg.transcribe.cpu "--cpu"}; then
          printf 'event=transcribe_failed\n' >&2
        fi
      ''}
      mkdir -p "$vault"
      kollate-cli --library "$library" export obsidian "$vault"

      printf '%s\n' "$stamp" >"$state/last-stamp"
      now >"$state/last-success"
      printf 'event=synced vault=%q\n' "$vault" >&2
    '';
  };

  koboSyncStale = pkgs.writeShellApplication {
    name = "kobo-sync-stale-check";
    runtimeInputs = with pkgs; [ coreutils libnotify ];
    text = ''
      last=''${XDG_STATE_HOME:-$HOME/.local/state}/kobo-sync/last-success
      # No file means the Kobo was never set up; nothing to warn about yet.
      [[ -f $last ]] || exit 0
      age_days=$(( ($(date -u +%s) - $(date -u -d "$(<"$last")" +%s)) / 86400 ))
      if ((age_days > ${toString cfg.staleAfterDays})); then
        notify-send --app-name=kobo-sync "Kobo not synced" \
          "Last sync $(<"$last"). Wake the Kobo on Wi-Fi, or re-run Cobalt setup after a firmware update."
      fi
    '';
  };
in {
  options.modules.koboSync = {
    enable = lib.mkEnableOption "pulling Kobo highlights, markups and notebooks into Obsidian over Wi-Fi";

    host = lib.mkOption {
      type = lib.types.str;
      default = "kobo";
      description = ''
        Hostname or IP of the Kobo. Needs to resolve to the reader: give it a
        DHCP reservation and a DNS name, or set the IP here.
      '';
    };

    sshKey = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.ssh/kobo_cobalt";
      description = "Private key that Cobalt's installer authorised for root on the Kobo.";
    };

    exportFolder = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/obsidian/3. Resources/Kobo";
      description = "Vault folder that kollate-cli's Obsidian export writes into.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "How often to try the Kobo. It only answers while awake on Wi-Fi.";
    };

    staleAfterDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Notify when the last successful sync is older than this.";
    };

    transcribe = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run kollate-cli transcribe on new handwriting before exporting.";
      };
      cpu = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Transcribe on the CPU instead of through Vulkan.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ koboSync pkgs.kollate-cli ];

    systemd.user.services.kobo-sync = {
      Unit.Description = "Pull Kobo annotations into Obsidian";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe koboSync;
        Nice = 10;
      };
    };
    systemd.user.timers.kobo-sync = {
      Unit.Description = "Poll the Kobo for new annotations";
      Timer = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.interval;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.kobo-sync-stale = {
      Unit.Description = "Warn when the Kobo has not synced for a while";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe koboSyncStale;
      };
    };
    systemd.user.timers.kobo-sync-stale = {
      Unit.Description = "Daily Kobo sync freshness check";
      Timer = {
        OnCalendar = "daily";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
