{ config
, pkgs
, lib
, ...
}: {
  services = {
    greetd = {
      enable = true;
    };
  };

  programs = {
    regreet = {
      enable = true;

      settings = {
        env = {
          STATE_DIR = "/var/lib/regreet";
        };
      };
    };
  };

  security.pam.services.greetd.kwallet.enable = true;
  # system.activationScripts.makeRegreetLibDir = lib.stringAfter [ "var" ] ''
  #   mkdir -p /var/lib/regreet
  #   chown greeter:greeter -R /var/lib/regreet
  # '';

  # environment.systemPackages = with pkgs; [
  #   greetd.regreet
  # ];

  environment.persistence.${config.modules.base.impermanencePersistencePath}.directories =
    lib.mkIf config.modules.base.enableImpermanence [
      {
        directory = "/var/lib/regreet";
        user = "greeter";
        group = "greeter";
        mode = "u=rwx,g=rx,o=";
      }
    ];
}
