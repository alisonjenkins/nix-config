{ config, lib, ... }:
let
  cfg = config.modules.hardware-fingerprint;
in
{
  options.modules.hardware-fingerprint = {
    enable = lib.mkEnableOption "fingerprint reader support (fprintd)";

    username = lib.mkOption {
      type = lib.types.str;
      description = "Username to enable fingerprint PAM authentication for.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.fprintd = {
      enable = true;
    };

    security.pam.services.${cfg.username}.fprintAuth = true;

    environment.persistence.${config.modules.base.impermanencePersistencePath}.directories =
      lib.mkIf config.modules.base.enableImpermanence [
        "/var/lib/fprint"
      ];
  };
}
