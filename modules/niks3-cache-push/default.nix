{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.niks3CachePush;
  niks3 = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;

  postBuildHook = pkgs.writeShellScript "niks3-queue-hook" ''
    set -euf
    echo "$OUT_PATHS" >> /var/lib/niks3-queue/queue
  '';

  drainScript = pkgs.writeShellScript "niks3-drain" ''
    set -euf
    QUEUE=/var/lib/niks3-queue/queue
    PROCESSING=/var/lib/niks3-queue/processing

    # Atomically swap queue to processing
    mv "$QUEUE" "$PROCESSING" 2>/dev/null || exit 0

    AUTH_TOKEN="$(cat "${cfg.authTokenFile}")"

    # Push all queued paths
    cat "$PROCESSING" | xargs -r ${lib.getExe niks3} push \
      --server-url "${cfg.serverUrl}" \
      --max-concurrent-uploads ${toString cfg.maxConcurrentUploads} \
      --auth-token "$AUTH_TOKEN"

    rm -f "$PROCESSING"
  '';
in
{
  options.modules.niks3CachePush = {
    enable = lib.mkEnableOption "queue-based niks3 binary cache push";

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.nixcache.org";
      description = "niks3 server URL to push store paths to";
    };

    maxConcurrentUploads = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Maximum number of concurrent uploads to the cache server";
    };

    authTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the niks3 auth token";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = postBuildHook;

    systemd.tmpfiles.rules = [
      "d /var/lib/niks3-queue 0770 root root -"
    ];

    systemd.paths.niks3-cache-push = {
      description = "Watch niks3 queue for new store paths";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/var/lib/niks3-queue/queue";
      };
    };

    systemd.services.niks3-cache-push = {
      description = "Push queued store paths to niks3 binary cache";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = drainScript;
      };
    };
  };
}
