{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.niks3CachePush;
in
{
  # On NixOS, delegate the post-build-hook + upload daemon to upstream's
  # niks3-auto-upload module (systemd socket-activated `niks3-hook serve`).
  # We keep `modules.niks3CachePush` as the single cross-platform interface
  # and just map our options onto `services.niks3-auto-upload`.
  imports = [ ./common.nix inputs.niks3.nixosModules.niks3-auto-upload ];

  config = lib.mkIf cfg.enable {
    services.niks3-auto-upload = {
      enable = true;
      package = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3-hook;
      serverUrl = cfg.serverUrl;
      authTokenFile = toString cfg.authTokenFile;
      socketPath = cfg.socketPath;
      batchSize = cfg.batchSize;
      idleExitTimeout = cfg.idleExitTimeout;
      maxConcurrentUploads = cfg.maxConcurrentUploads;
      verifyS3Integrity = cfg.verifyS3Integrity;
      debug = cfg.debug;
    };
  };
}
