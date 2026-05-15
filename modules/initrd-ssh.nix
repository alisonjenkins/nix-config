{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.initrd-ssh;
in {
  options.modules.initrd-ssh = {
    enable = mkEnableOption "SSH server inside initrd for debugging stuck boots";

    port = mkOption {
      type = types.port;
      default = 2222;
      description = ''
        Port for the initrd SSH server. Kept distinct from the main
        sshd (22) so a forwarded client doesn't accidentally treat a
        post-boot connection as an initrd one.
      '';
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      description = ''
        Public keys allowed to log in to the initrd SSH server as root.
        The initrd has no users other than root.
      '';
    };

    hostKeyPath = mkOption {
      type = types.path;
      default = "/etc/secrets/initrd/ssh_host_ed25519_key";
      description = ''
        Path to an existing ED25519 private host key for the initrd
        SSH server. Generate once on the target host before enabling:
            sudo mkdir -p /etc/secrets/initrd
            sudo ssh-keygen -t ed25519 -N "" -f /etc/secrets/initrd/ssh_host_ed25519_key
            sudo chmod 600 /etc/secrets/initrd/ssh_host_ed25519_key

        WARNING: the host key is bundled into the initrd cpio on the
        unencrypted ESP. Physical access to the device permits
        impersonation of the initrd SSH server. Acceptable for
        debugging on a trusted network; disable when not needed.
      '';
    };

    extraKernelModules = mkOption {
      type = types.listOf types.str;
      default = [
        # USB-Ethernet drivers — covers Realtek r815x, ASIX AX88xxx,
        # Cypress USB-NIC. Loaded as availableKernelModules so udev
        # binds them only if the device is present.
        "r8152"
        "asix"
        "ax88179_178a"
        "cdc_ether"
        "usbnet"
      ];
      description = ''
        NIC kernel modules added to the initrd as
        availableKernelModules. Default covers common USB-Ethernet
        adapters. PCIe wired NICs (e1000e, igc, r8169, etc.) usually
        come in from the hardware-configuration.nix auto-detection,
        but add them here if not.
      '';
    };

    wifi = {
      enable = mkEnableOption "wifi support inside initrd (driver + firmware + wpa_supplicant)";

      interface = mkOption {
        type = types.str;
        description = ''
          Wifi interface name (check `ip -br link` on the running
          system, e.g. "wlo1", "wlp3s0").
        '';
      };

      driverModules = mkOption {
        type = types.listOf types.str;
        default = ["ath11k_pci" "ath11k"];
        description = ''
          Wifi driver modules force-loaded in the initrd.
          Defaults to ath11k for Steam Deck (Qualcomm QCNFA765).
          Other common choices: brcmfmac (Cypress), rtw89_8852ce
          (Realtek 8852CE), iwlwifi (Intel), mt76 (MediaTek).
        '';
      };

      ssid = mkOption {
        type = types.str;
        description = "SSID to associate with from the initrd.";
      };

      pskFile = mkOption {
        type = types.path;
        description = ''
          Path to a file containing the WPA2 PSK only (no trailing
          newline). Generate once on the target host:
              echo -n 'YOUR_WIFI_PSK' | sudo tee /etc/secrets/initrd/wifi.psk
              sudo chmod 600 /etc/secrets/initrd/wifi.psk

          WARNING: the PSK ends up inside the initrd cpio on the
          unencrypted ESP. Physical access to the device leaks the
          PSK. For long-term security, rotate the PSK after
          debugging and disable initrd-ssh when not in use.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = ''
          modules.initrd-ssh requires boot.initrd.systemd.enable =
          true. The scripted (busybox) initrd path is not supported
          by this module.
        '';
      }
      # NOTE: We don't assert on `pathExists hostKeyPath` because
      # `builtins.pathExists` of an absolute path outside the flake
      # source returns false in pure-eval mode regardless of whether
      # the file exists. Building this module requires --impure;
      # the underlying readFile / fileContents will produce a clear
      # error if the host key or PSK is missing at build time.
    ];

    # Firmware bundling: redistributable firmware in /run/current-system
    # /firmware is automatically copied into the initrd by the systemd
    # stage 1 generator when a kernel module that requests it is in
    # initrd.kernelModules. Make sure the metapackage is pulled in.
    hardware.enableRedistributableFirmware = mkIf cfg.wifi.enable (mkDefault true);

    boot.initrd = {
      availableKernelModules =
        cfg.extraKernelModules
        ++ optionals cfg.wifi.enable cfg.wifi.driverModules;

      # Force-load wifi drivers early so the interface exists before
      # systemd-networkd tries to configure it.
      kernelModules = optionals cfg.wifi.enable cfg.wifi.driverModules;

      network = {
        enable = true;
        ssh = {
          enable = true;
          inherit (cfg) port authorizedKeys;
          hostKeys = [cfg.hostKeyPath];
        };
      };

      systemd = {
        network = {
          enable = true;
          networks."10-initrd-net" = {
            matchConfig.Name =
              if cfg.wifi.enable
              then cfg.wifi.interface
              else "en* eth*";
            DHCP = "yes";
            linkConfig.RequiredForOnline = "routable";
          };
        };

        # Bundle wpa_supplicant into the initrd and bring up the wifi
        # link before systemd-networkd configures the interface.
        storePaths = mkIf cfg.wifi.enable [
          "${pkgs.wpa_supplicant}/bin/wpa_supplicant"
        ];

        contents = mkIf cfg.wifi.enable {
          # PSK is read from a file outside the Nix store, embedded
          # into a small config that lives in initrd cpio.
          "/etc/wpa_supplicant-initrd.conf".source = pkgs.writeText "wpa_supplicant-initrd.conf" ''
            ctrl_interface=DIR=/run/wpa_supplicant
            update_config=0
            network={
              ssid="${cfg.wifi.ssid}"
              psk="${lib.removeSuffix "\n" (builtins.readFile cfg.wifi.pskFile)}"
              scan_ssid=1
              key_mgmt=WPA-PSK
            }
          '';
        };

        services.wpa_supplicant-initrd = mkIf cfg.wifi.enable {
          description = "wpa_supplicant for initrd wifi";
          wantedBy = ["initrd.target"];
          before = ["systemd-networkd.service"];
          after = ["systemd-udev-trigger.service"];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.wpa_supplicant}/bin/wpa_supplicant -i ${cfg.wifi.interface} -c /etc/wpa_supplicant-initrd.conf";
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      };
    };
  };
}
