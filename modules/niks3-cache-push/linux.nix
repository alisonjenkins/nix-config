{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.niks3CachePush;
  niks3 = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;
  scripts = import ./scripts.nix { inherit pkgs lib cfg niks3; };
in
{
  imports = [ ./common.nix ];

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${scripts.queueDir} 0770 root root -"
    ];

    systemd.paths.niks3-cache-push = {
      description = "Watch niks3 queue for new store paths";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = scripts.queueFile;
      };
    };

    systemd.services.niks3-cache-push = {
      description = "Push queued store paths to niks3 binary cache";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = scripts.drainScript;
      };
    };
  };
}
