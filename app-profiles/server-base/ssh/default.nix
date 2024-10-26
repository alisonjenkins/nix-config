{ ... }: {
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PermitRootLogin = "no";
    hostKeys = [
      {
        bits = 4096;
        path = "/etc/ssh/ssh_host_rsa_key";
        rounds = 100;
        type = "rsa";
      }
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        rounds = 100;
        type = "ed25519";
      }
    ];
  };
}
