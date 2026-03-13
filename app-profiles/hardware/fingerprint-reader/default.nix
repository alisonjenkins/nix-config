{ config, lib, username, ... }: {
  services.fprintd = {
    enable = true;
  };

  security.pam.services.${username}.fprintAuth = true;

  environment.persistence.${config.modules.base.impermanencePersistencePath}.directories =
    lib.mkIf config.modules.base.enableImpermanence [
      "/var/lib/fprint"
    ];
}
