{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.modules.initrd-ssh;

  # Ephemeral ED25519 host key generated as part of the build. Nix
  # caches the derivation output by .drv hash — same nixpkgs + same
  # comment string = same key on subsequent rebuilds. New nixpkgs
  # rev (or `nix-collect-garbage`) regenerates the key, which means
  # the next initrd-SSH connection will warn about a changed host
  # key. Clear with `ssh-keygen -R "[ip]:port"`. For a stable key
  # across all rebuilds, override boot.initrd.network.ssh.hostKeys
  # downstream of this module to point at a real path.
  ephemeralHostKey = pkgs.runCommandLocal "initrd-ssh-host-key" {
    nativeBuildInputs = [pkgs.openssh];
  } ''
    ssh-keygen -t ed25519 -N "" -f $out -C "initrd-ssh-build-time-${cfg.hostKeyComment}"
  '';
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

    hostKeyComment = mkOption {
      type = types.str;
      default = "initrd-ssh";
      description = ''
        Comment baked into the auto-generated initrd SSH host key.
        Mostly cosmetic — visible via `ssh-keygen -lf`.
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
          Path on the TARGET host (read at activation time, not at
          flake-eval time) to a file containing the WPA2 PSK only,
          no trailing newline. Generate once on the target:
              echo -n 'YOUR_WIFI_PSK' \
                  | sudo tee /etc/secrets/initrd/wifi.psk
              sudo chmod 600 /etc/secrets/initrd/wifi.psk

          The file is copied into the initrd cpio at switch time via
          boot.initrd.secrets — it is NOT read by the build host, so
          building on a workstation works without any local secret
          files.

          WARNING: the PSK still ends up inside the initrd cpio on
          the unencrypted ESP. Physical access to the device leaks
          the PSK. Rotate the PSK after debugging and disable
          initrd-ssh when not in use.
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
          hostKeys = [ephemeralHostKey];
        };
      };

      # PSK lives outside the Nix store. boot.initrd.secrets copies
      # it into the cpio at activation time on the TARGET host (not
      # at flake-eval time on the build host) — so building on a
      # workstation needs no /etc/secrets/* files locally.
      secrets = mkIf cfg.wifi.enable {
        "/etc/initrd-ssh/wifi.psk" = cfg.wifi.pskFile;
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

        # Bundle wpa_supplicant + the helpers used by the
        # ExecStartPre conf-rendering script into the initrd.
        storePaths = mkIf cfg.wifi.enable [
          "${pkgs.wpa_supplicant}/bin/wpa_supplicant"
          "${pkgs.coreutils}/bin/cat"
          "${pkgs.gnused}/bin/sed"
        ];

        # Bake a TEMPLATE conf into the initrd at build time. The
        # PSK placeholder is replaced at boot by ExecStartPre using
        # the activation-time secret at /etc/initrd-ssh/wifi.psk.
        contents = mkIf cfg.wifi.enable {
          "/etc/wpa_supplicant-initrd.conf.template".source = pkgs.writeText "wpa_supplicant-initrd.conf.tpl" ''
            ctrl_interface=DIR=/run/wpa_supplicant
            update_config=0
            network={
              ssid="${cfg.wifi.ssid}"
              psk="@PSK@"
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
            # Render the real conf at boot by interpolating the
            # activation-time secret into the template.
            ExecStartPre = pkgs.writeShellScript "render-wpa-conf" ''
              set -euo pipefail
              psk=$(${pkgs.coreutils}/bin/cat /etc/initrd-ssh/wifi.psk)
              ${pkgs.gnused}/bin/sed "s|@PSK@|$psk|" \
                /etc/wpa_supplicant-initrd.conf.template \
                > /run/wpa_supplicant-initrd.conf
            '';
            ExecStart = "${pkgs.wpa_supplicant}/bin/wpa_supplicant -i ${cfg.wifi.interface} -c /run/wpa_supplicant-initrd.conf";
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
      };
    };
  };
}
