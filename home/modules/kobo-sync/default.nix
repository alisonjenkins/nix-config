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
    runtimeInputs = with pkgs; [ coreutils gnugrep openssh gnutar rsync sqlite kollate-cli ];
    text = ''
      host=${lib.escapeShellArg cfg.host}
      ssh_key=${lib.escapeShellArg cfg.sshKey}
      vault=${lib.escapeShellArg cfg.exportFolder}
      stamp_paths=${lib.escapeShellArg (remoteQuote stampPaths)}
      sync_paths=${lib.escapeShellArg (remoteQuote syncPaths)}
      transcribe=${if !cfg.transcribe.enable then "off" else if cfg.transcribe.cpu then "cpu" else "gpu"}
    '' + builtins.readFile ./kobo-sync.sh;
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
