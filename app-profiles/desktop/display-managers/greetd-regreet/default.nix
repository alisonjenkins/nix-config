{ pkgs
, ...
}: {
  services = {
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.regreet}/bin/regreet";
        };
      };
    };
  };

  security.pam.services.greetd.enableKwallet = true;

  environment.systemPackages = with pkgs; [
    greetd.regreet
  ];
}
