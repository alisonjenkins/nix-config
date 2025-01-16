{ consoleKeyMap ? "us"
, timezone ? "Europe/London"
, enableMesaGit ? false
,
}: {
  console.keyMap = consoleKeyMap;
  hardware.pulseaudio.enable = false;
  time.timeZone = timezone;

  chaotic = {
    mesa-git = {
      enable = enableMesaGit;
    };
  };

  security = {
    rtkit.enable = true;

    sudo = {
      enable = true;
      wheelNeedsPassword = true;
    };
  };

  services = {
    fstrim.enable = true;
    irqbalance.enable = true;
    resolved.enable = true;

    earlyoom = {
      enable = true;
      enableNotifications = true;
    };

    openssh = {
      enable = true;

      hostKeys = [
        {
          bits = 4096;
          path = "/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
        }
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];

      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
  };

  zramSwap = {
    enable = true;
  };
}
