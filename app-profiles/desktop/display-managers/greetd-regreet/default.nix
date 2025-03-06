{ pkgs
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

  security.pam.services.greetd.enableKwallet = true;
  # system.activationScripts.makeRegreetLibDir = lib.stringAfter [ "var" ] ''
  #   mkdir -p /var/lib/regreet
  #   chown greeter:greeter -R /var/lib/regreet
  # '';

  # environment.systemPackages = with pkgs; [
  #   greetd.regreet
  # ];
}
