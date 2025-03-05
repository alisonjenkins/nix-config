{ pkgs
, lib
, ...
}: {
  services = {
    greetd = {
      enable = true;
      # settings = {
      #   default_session = {
      #     command = "${pkgs.cage}/bin/cage -s -- ${pkgs.greetd.regreet}/bin/regreet";
      #   };
      # };
    };
  };

  programs = {
    regreet = {
      enable = true;
    };
  };

  security.pam.services.greetd.enableKwallet = true;
  # system.activationScripts.makeRegreetLogDir = lib.stringAfter [ "var" ] ''
  #   mkdir -p /var/log/regreet
  #   chown greeter:greeter -R /var/log/regreet
  # '';

  # environment.systemPackages = with pkgs; [
  #   greetd.regreet
  # ];
}
