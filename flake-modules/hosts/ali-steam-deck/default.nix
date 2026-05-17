{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.ali-steam-deck = lib.nixosSystem rec {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.ali-steam-deck-disko-config
      self.nixosModules.ali-steam-deck-hardware
      self.nixosModules.desktop-1password
      self.nixosModules.desktop-aws-tools
      self.nixosModules.desktop-base
      self.nixosModules.desktop-kubernetes
      self.nixosModules.desktop-media
      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.locale
      self.nixosModules.luks-controller-unlock
      self.nixosModules.initrd-ssh

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.jovian-nixos.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default

      # Home-manager configuration
      {
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${specialArgs.username} = {
          imports = [ self.homeModules.home-linux ];
        };
        home-manager.extraSpecialArgs =
          specialArgs
          // {
            hostname = "ali-steam-deck";
            bluetoothHeadsetMac = "";
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "";
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "github.com";
            github_clone_ssh_host_work = "github.com";
            primarySSHKey = "~/.ssh/id_personal.pub";
          };
      }

      # Pull in repo-wide overlays. `modifications` is where the
      # openldap doCheck=false override lives (NixOS/nixpkgs#372569
      # workaround), plus xrdb / claude-code / direnv pins. Without
      # this the overrides never reach this host's nixpkgs and the
      # openldap test failure resurfaces during nixos-install.
      {
        nixpkgs.overlays = [
          self.overlays.additions
          self.overlays.modifications
          # Decky plugin management is intentionally NOT declarative: every
          # nix-based approach we tried (schradert/nur git-build,
          # buildDeckyPlugin via pnpm, fetching Decky store zips into
          # pkgs.deckyPlugins) broke at runtime — either pnpm/Python toolchain
          # mismatches, missing plugin subdirectories that the installPhase
          # didn't preserve, or React-error-#130 frontend crashes when even
          # one plugin's bundle wasn't byte-identical to the maintainer's
          # build. Decky's own in-Steam plugin browser handles all of this
          # correctly; we just persist /var/lib/decky-loader so its installs
          # survive impermanence (see persistence block in the host config
          # below).
        ];
      }

      # Host-specific configuration
      ({ lib, outputs, pkgs, username, ... }: {
        modules.base = {
          enable = true;
          bootLoader = "grub";
          enableImpermanence = true;
          impermanencePersistencePath = "/persistence";
          enableCachyOSKernel = false;
          beesdFilesystems = {
            crypted = {
              spec = "LABEL=crypted";
              hashTableSizeMB = 256;
              verbosity = "crit";
              extraOptions = [ "--loadavg-target" "5.0" ];
            };
          };
        };

        modules.desktop.enable = true;
        modules.desktop-1password.enable = true;
        modules.desktop-aws-tools.enable = true;
        modules.desktop-base.enable = true;
        modules.desktop-kubernetes.enable = true;
        modules.desktop-media.enable = true;
        modules.locale.enable = true;

        boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
        boot.loader.grub.efiInstallAsRemovable = lib.mkForce true;

        # TPM2-based LUKS auto-unlock so the Steam Deck doesn't need
        # a USB keyboard at boot to type the password. systemd-stage-1
        # is required for systemd-cryptsetup's TPM2 support — scripted
        # stage-1 (the default) cannot unseal TPM-bound keys.
        # The TPM is enrolled as an additional keyslot during install
        # by the install-nixos launcher; the original password keyslot
        # stays as a fallback for the case where PCR 7 changes
        # (UEFI Secure Boot toggle).
        boot.initrd.systemd.enable = true;
        boot.initrd.availableKernelModules = [ "tpm_crb" ];
        boot.initrd.luks.devices."crypted".crypttabExtraOpts = [
          # TEMPORARY: systemd 258.7's systemd-cryptsetup segfaults in
          # libsystemd-shared.so during the TPM2 unlock attempt (seen
          # in initrd journal: ".systemd-crypts[231]: segfault at 8 ip
          # ... in libsystemd-shared-258.so"). The crash happens after
          # "Successfully created primary key on TPM in 129ms" and
          # before keyfile / ask-password fallback. Disabling the TPM2
          # plugin sends cryptsetup straight to the keyfile-miss →
          # ask-password path, which lets luks-controller-unlock
          # actually receive the prompt. Re-enable once systemd is
          # patched (upstream or NixOS revert).
          # "tpm2-device=auto"
          # Bypass kernel workqueues for dm-crypt — significant
          # NVMe I/O improvement on a CPU with hardware AES (Zen 2
          # has AES-NI, so the actual crypto is near-free; the
          # workqueue latency was dominating).
          "no-read-workqueue"
          "no-write-workqueue"
        ];

        # Game-controller fallback unlock. TPM2 is tried first and
        # silently unseals 99% of boots. The agent only draws when
        # systemd-cryptsetup falls through to ask-password — typically
        # after a Secure Boot / firmware change invalidates the PCR
        # binding. Keyboard passphrase keyslot remains the ultimate
        # fallback (intentionally NOT masking the console agent until
        # a week of clean reboots — see TESTING.md rung 5.3).
        modules.luks-controller-unlock = {
          enable = true;
          maskConsoleAgent = true;
          # TEMP: re-enabled to diagnose "agent reply doesn't unlock"
          # — captures "agent: replied N bytes" so we can check the
          # length against the enrolled PIN. The wrapper is currently
          # at -v (debug, not trace) so no per-button bytes leak. Set
          # back to null after the keyslot mismatch is resolved.
          debugLogToEsp = "/dev/nvme0n1p2";
        };

        # SSH server inside initrd for debugging stuck boots. Wired
        # for wifi via ath11k (Qualcomm QCNFA765) since the Deck has
        # no built-in ethernet and we typically debug without a dock.
        # The PSK and host key live outside the Nix store at the
        # paths below — generate them once on the device before
        # rebuilding:
        #   sudo mkdir -p /etc/secrets/initrd
        #   sudo ssh-keygen -t ed25519 -N "" \
        #       -f /etc/secrets/initrd/ssh_host_ed25519_key
        #   echo -n 'YOUR_WIFI_PSK' \
        #       | sudo tee /etc/secrets/initrd/wifi.psk >/dev/null
        #   sudo chmod 600 /etc/secrets/initrd/*
        # Disable this module after the agent regression is fixed —
        # initrd cpio sits on the unencrypted ESP, so anyone with
        # physical access can extract the PSK + impersonate the
        # host key.
        modules.initrd-ssh = {
          enable = false;
          port = 2222;
          authorizedKeys = [ outputs.lib.sshKeys.primary ];
          wifi = {
            enable = true;
            interface = "wlo1";
            ssid = "jenkins";
            pskFile = "/etc/secrets/initrd/wifi.psk";
          };
        };

        # Let Jovian's custom Jupiter mesa override the desktop module's unstable mesa
        hardware.graphics.package = lib.mkForce pkgs.mesa;
        hardware.graphics.package32 = lib.mkForce pkgs.pkgsi686Linux.mesa;

        # Disable desktop-base's gamescope wrapper — Jovian provides its own
        programs.gamescope.enable = lib.mkForce false;

        # Resolve conflict: Jovian sets true, base module sets 1 (same meaning)
        boot.kernel.sysctl."net.ipv4.tcp_mtu_probing" = lib.mkForce 1;

        # (Debug kernelparams removed — they were forwarding the
        # systemd journal to tty1 after pivot, which blocked
        # SDDM/getty from rendering Steam Big Picture. The LUKS
        # path is stable now; re-enable selectively if a future
        # initrd issue needs diagnosing.)

        # Jovian manages the power button via its own daemon (powerbuttond)
        services.logind.settings.Login.HandlePowerKey = lib.mkForce "ignore";


        environment = {
          pathsToLink = [ "/share/zsh" ];

          variables = {
            PATH = [
              "\${HOME}/.local/bin"
              "\${HOME}/.config/rofi/scripts"
            ];
            ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
          };
        };

        jovian = {
          devices.steamdeck.enable = true;
          decky-loader = {
            enable = true;
            # Jovian's decky-loader.nix sets `systemd.services.decky-loader.path`
            # strictly to `cfg.extraPackages` — no system fallback. Decky's
            # init queries `systemctl is-active <service>`; without systemd
            # on the unit PATH that call FileNotFoundErrors and floods the
            # log. Adding systemd silences the noise and lets plugins that
            # shell out to systemctl work too.
            extraPackages = [ pkgs.systemd ];
          };

          steam = {
            enable = true;
            autoStart = true;
            user = username;
            desktopSession = "plasma";
          };
        };

        # Decky's frontend only loads if Steam was started with CEF remote
        # debugging enabled, which Steam keys off the presence of this
        # sentinel file. Jovian's decky-loader docs treat creating it as
        # an imperative step; do it declaratively here so a fresh install
        # boots into a working Decky UI without manual intervention.
        # Tracked in https://github.com/Jovian-Experiments/Jovian-NixOS/issues/460
        #
        # Target the resolved Steam path, not ~/.steam/steam — the latter is
        # a symlink (~/.steam/steam → ~/.local/share/Steam), which
        # systemd-tmpfiles refuses to traverse with "unsafe path transition".
        # Steam creates ~/.local/share/Steam on first run; the file rule
        # alone is enough — no parent directory creation needed.
        systemd.tmpfiles.rules = [
          "f /home/${username}/.local/share/Steam/.cef-enable-remote-debugging 0644 ${username} users -"
        ];

        # Persist Decky's state dir across reboots so plugins the user
        # installs from inside Decky survive the impermanence tmpfs wipe.
        # decky-loader runs as the `decky` system user (Jovian module
        # default); stateDir matches.
        environment.persistence."/persistence".directories = [
          {
            directory = "/var/lib/decky-loader";
            user = "decky";
            group = "decky";
            mode = "0700";
          }
        ];

        networking = {
          hostName = "ali-steam-deck";
          extraHosts = ''
            192.168.1.202 home-kvm-hypervisor-1
          '';
        };

        programs.steam = {
          remotePlay.openFirewall = true;
          dedicatedServer.openFirewall = true;
        };

        services.btrfs.autoScrub = {
          enable = true;
          fileSystems = [ "/persistence" ];
        };

        # Persist the journal so if Steam Big Picture / SDDM falls
        # through to a tty bash shell, the failure cause is
        # recoverable from /persistence/var/log/journal/ via a
        # subsequent installer boot. Default Storage=auto only
        # persists when /var/log/journal already exists — which it
        # doesn't on a fresh impermanence root.
        services.journald.extraConfig = ''
          Storage=persistent
          SystemMaxUse=200M
        '';

        services.desktopManager.plasma6.enable = true;

        # Stylix theme is configured by the desktop module (gruvbox-dark-medium).

        system.stateVersion = "24.05";

        users.users.ali = {
          isNormalUser = true;
          description = "Alison Jenkins";
          initialPassword = "initPw!";
          extraGroups = [ "networkmanager" "wheel" "docker" "realtime" ];
          openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];
          packages = with pkgs; [
            citron
            fastfetch
            firefox
          ];
        };

        # Remote diagnostics: authorize the primary key for root so a
        # boot that lands at a tty bash shell (no keyboard available)
        # can still be inspected via SSH over Tailscale without
        # needing the sudo password. Tailscale auth state persists in
        # /var/lib/tailscale (impermanence-pinned) so the link comes
        # up automatically when multi-user.target is reached.
        users.users.root.openssh.authorizedKeys.keys = [
          outputs.lib.sshKeys.primary
        ];
        services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";

        xdg.portal = {
          enable = true;
          xdgOpenUsePortal = true;
        };

        # Desktop-only specialisation: boots directly into Plasma instead of
        # Gaming Mode. Selectable from GRUB at boot. Useful as a recovery
        # option when Steam's state is broken and Gaming Mode won't start.
        specialisation.desktop-mode.configuration = {
          jovian.steam.autoStart = lib.mkForce false;

          services.greetd = {
            enable = true;
            settings.default_session = {
              command = "${pkgs.kdePackages.plasma-workspace}/libexec/plasma-dbus-run-session-if-needed ${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland";
              user = username;
            };
          };

          system.nixos.tags = [ "desktop-mode" ];
        };
      })
    ];
  };
}
