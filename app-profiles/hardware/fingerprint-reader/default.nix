{ username, ... }: {
  services.fprintd = {
    enable = true;
  };

  security.pam.services.${username}.fprintAuth = true;
}
