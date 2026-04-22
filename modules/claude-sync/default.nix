{ config, lib, pkgs, ... }:
let
  cfg = config.modules.claudeSync;

  syncIncludes = [
    "projects/*/memory/**"
    "projects/*/*.jsonl"
    "plans/**"
    "todos/**"
    "tasks/**"
  ];

  syncExcludes = [
    "file-history/**"
    "cache/**"
    "image-cache/**"
    "paste-cache/**"
    "shell-snapshots/**"
    "session-env/**"
    "statsig/**"
    "ide/**"
    "backups/**"
    "telemetry/**"
    "debug/**"
    ".credentials.json"
    "history.jsonl"
    "stats-cache.json"
    "mcp-needs-auth-cache.json"
  ];

  filterFile = pkgs.writeText "claude-sync.filter" (
    lib.concatStringsSep "\n" (
      (map (p: "+ ${p}") syncIncludes)
      ++ (map (p: "- ${p}") syncExcludes)
      ++ [ "- **" ]
    ) + "\n"
  );

  homeDir = "/home/${cfg.user}";
  claudeDir = "${homeDir}/.claude";
  stateDir = "${homeDir}/.local/state/rclone-claude-sync";
  lockFile = "${claudeDir}/.sync.lock";

  syncScript = pkgs.writeShellApplication {
    name = "claude-sync";
    runtimeInputs = with pkgs; [ rclone util-linux coreutils ];
    text = ''
      set -uo pipefail

      mkdir -p "${claudeDir}" "${stateDir}"

      # Serialize with flock so hook-, timer-, and suspend-triggered runs don't race.
      exec 9>"${lockFile}"
      if ! flock -n 9; then
        echo "claude-sync: another sync already running, exiting"
        exit 0
      fi

      if [ ! -f "${stateDir}/.bootstrapped" ]; then
        echo "claude-sync: bisync state not bootstrapped. Run 'just claude-sync-bootstrap' first."
        exit 0
      fi

      # Conflict handling: on a both-sides-modified file, newer wins and the
      # loser is renamed with a .conflict-old.YYYYMMDD-HHMMSS suffix so the
      # user can recover it if needed. In practice collisions are rare because
      # session .jsonl filenames are uuid-based (per-machine).
      rclone bisync \
        "${claudeDir}" \
        "${cfg.remote}:" \
        --filter-from "${filterFile}" \
        --workdir "${stateDir}" \
        --conflict-resolve newer \
        --conflict-suffix conflict-old \
        --max-lock 2m \
        --resilient \
        --recover \
        --compare size,modtime \
        --create-empty-src-dirs \
        --log-level INFO
    '';
  };

  bootstrapScript = pkgs.writeShellApplication {
    name = "claude-sync-bootstrap";
    runtimeInputs = with pkgs; [ rclone coreutils systemd ];
    text = ''
      set -euo pipefail

      if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
        XDG_RUNTIME_DIR="/run/user/$(id -u)"
        export XDG_RUNTIME_DIR
      fi

      echo "==> Pausing claude-sync.timer (if running)..."
      systemctl --user stop claude-sync.timer 2>/dev/null || true

      mkdir -p "${claudeDir}" "${stateDir}"

      echo "==> Running initial bisync --resync against ${cfg.remote}:..."
      rclone bisync \
        "${claudeDir}" \
        "${cfg.remote}:" \
        --filter-from "${filterFile}" \
        --workdir "${stateDir}" \
        --resync \
        --create-empty-src-dirs \
        --log-level INFO

      touch "${stateDir}/.bootstrapped"

      echo "==> Starting claude-sync.timer..."
      systemctl --user start claude-sync.timer

      echo "==> Bootstrap complete."
    '';
  };

  envFilePath = config.sops.templates."claude-sync.env".path;

  # Non-secret env vars needed by rclone. Secret values (B2 key, crypt password,
  # crypt salt) come from EnvironmentFile via sops.templates.
  rcloneEnvironment = {
    RCLONE_CONFIG_CLAUDE_SYNC_B2_TYPE = "b2";
    RCLONE_CONFIG_CLAUDE_SYNC_CRYPT_TYPE = "crypt";
    RCLONE_CONFIG_CLAUDE_SYNC_CRYPT_FILENAME_ENCODING = "base32";
    RCLONE_CONFIG_CLAUDE_SYNC_CRYPT_REMOTE = "claude-sync-b2:${cfg.bucket}";
    HOME = homeDir;
    XDG_STATE_HOME = "${homeDir}/.local/state";
    XDG_CONFIG_HOME = "${homeDir}/.config";
    XDG_CACHE_HOME = "${homeDir}/.cache";
  };
in
{
  options.modules.claudeSync = {
    enable = lib.mkEnableOption "sync of ~/.claude state to encrypted Backblaze B2 via rclone bisync";

    user = lib.mkOption {
      type = lib.types.str;
      description = "Username whose ~/.claude directory is synced.";
      example = "ali";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      description = "Backblaze B2 bucket name (non-secret).";
      example = "alison-claude-sync";
    };

    remote = lib.mkOption {
      type = lib.types.str;
      default = "claude-sync-crypt";
      description = ''
        rclone remote name referenced by the sync commands. Must match the
        name component used in the RCLONE_CONFIG_<REMOTE>_* env vars rendered
        by sops.templates."claude-sync.env".
      '';
    };

    intervalMinutes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = "Safety-net timer interval for periodic background sync.";
    };

    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the sops-encrypted yaml file containing the B2 credentials and
        rclone crypt passwords. Expected keys:
          b2_account_id, b2_application_key,
          rclone_crypt_password, rclone_crypt_salt
        The password values must already be passed through `rclone obscure`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.rclone
      syncScript
      bootstrapScript
    ];

    sops.secrets = {
      "claude-sync/b2_account_id" = {
        sopsFile = cfg.sopsFile;
        key = "b2_account_id";
      };
      "claude-sync/b2_application_key" = {
        sopsFile = cfg.sopsFile;
        key = "b2_application_key";
      };
      "claude-sync/rclone_crypt_password" = {
        sopsFile = cfg.sopsFile;
        key = "rclone_crypt_password";
      };
      "claude-sync/rclone_crypt_salt" = {
        sopsFile = cfg.sopsFile;
        key = "rclone_crypt_salt";
      };
    };

    sops.templates."claude-sync.env" = {
      owner = cfg.user;
      mode = "0400";
      content = ''
        RCLONE_CONFIG_CLAUDE_SYNC_B2_ACCOUNT=${config.sops.placeholder."claude-sync/b2_account_id"}
        RCLONE_CONFIG_CLAUDE_SYNC_B2_KEY=${config.sops.placeholder."claude-sync/b2_application_key"}
        RCLONE_CONFIG_CLAUDE_SYNC_CRYPT_PASSWORD=${config.sops.placeholder."claude-sync/rclone_crypt_password"}
        RCLONE_CONFIG_CLAUDE_SYNC_CRYPT_PASSWORD2=${config.sops.placeholder."claude-sync/rclone_crypt_salt"}
      '';
    };

    systemd.user.services.claude-sync = {
      description = "Sync ~/.claude state to encrypted B2 via rclone bisync";
      unitConfig.ConditionUser = cfg.user;
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = rcloneEnvironment;
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = envFilePath;
        ExecStart = lib.getExe syncScript;
        TimeoutStartSec = "10min";
      };
    };

    systemd.user.timers.claude-sync = {
      description = "Periodic safety-net sync of ~/.claude to B2";
      wantedBy = [ "timers.target" ];
      unitConfig.ConditionUser = cfg.user;
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString cfg.intervalMinutes}min";
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };

    # System-level service that runs as the user before suspend, so the laptop
    # flushes any unsynced memory / session transcripts to B2 before powering
    # off. Must be system-level because sleep.target is a system target.
    systemd.services.claude-sync-pre-suspend = {
      description = "Flush ~/.claude state to B2 before suspend";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      environment = rcloneEnvironment;
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = "users";
        EnvironmentFile = envFilePath;
        ExecStart = lib.getExe syncScript;
        TimeoutStartSec = "2min";
      };
    };

  };
}
