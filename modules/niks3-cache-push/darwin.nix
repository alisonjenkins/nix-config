{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.niks3CachePush;
  niks3 = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;
  scripts = import ./scripts.nix { inherit pkgs lib cfg niks3; };
in
{
  imports = [ ./common.nix ];

  config = lib.mkIf cfg.enable {
    system.activationScripts.niks3QueueDir.text = ''
      mkdir -p ${scripts.queueDir}
      chown root:wheel ${scripts.queueDir}
      chmod 0770 ${scripts.queueDir}
    '';

    launchd.daemons.niks3-cache-push.serviceConfig = {
      Label = "org.nixos.niks3-cache-push";
      ProgramArguments = [ (lib.getExe scripts.drainScript) ];
      WatchPaths = [ scripts.queueFile ];
      RunAtLoad = false;
      KeepAlive = false;
      StandardOutPath = "/var/log/niks3-cache-push.log";
      StandardErrorPath = "/var/log/niks3-cache-push.log";
    };
  };
}
