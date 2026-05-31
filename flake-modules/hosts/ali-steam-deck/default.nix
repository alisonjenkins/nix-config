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
      ({ config, lib, outputs, pkgs, username, ... }: {
        modules.base = {
          enable = true;
          bootLoader = "grub";
          enableImpermanence = true;
          impermanencePersistencePath = "/persistence";
          enableCachyOSKernel = false;
          # No btrfs after the XFS migration — beesd is btrfs-only.
        };

        # XFS doesn't support discard mount option (no perf benefit);
        # weekly fstrim keeps the SSD healthy instead.
        services.fstrim.enable = true;

        # Single XFS data LV (/persistence) is shared between /nix and
        # /home via bind mounts. XFS can grow but not shrink, so we
        # avoid pre-committing the split.
        boot.initrd.systemd.tmpfiles.settings."10-deck-data-binds" = {
          "/persistence/nix".d = { mode = "0755"; };
          "/persistence/home".d = { mode = "0755"; };
        };

        fileSystems."/nix" = {
          device = "/persistence/nix";
          fsType = "none";
          options = [ "bind" ];
          neededForBoot = true;
          depends = [ "/persistence" ];
        };

        fileSystems."/home" = {
          device = "/persistence/home";
          fsType = "none";
          options = [ "bind" ];
          depends = [ "/persistence" ];
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
          # Keyboard passphrase prompt left VISIBLE as a safety net while
          # the controller-unlock DRM timing (see wait-for-drm-card below)
          # is being stabilised on the 26.05 valve kernel. With the agent
          # masked, a DRM failure left no prompt at all → emergency mode.
          # Re-enable masking (true) once a week of clean controller-PIN
          # boots confirms the gate works — see TESTING.md rung 5.3.
          maskConsoleAgent = false;
          # TEMP: re-enabled to diagnose "agent reply doesn't unlock"
          # — captures "agent: replied N bytes" so we can check the
          # length against the enrolled PIN. The wrapper is currently
          # at -v (debug, not trace) so no per-button bytes leak. Set
          # back to null after the keyslot mismatch is resolved.
          debugLogToEsp = "/dev/nvme0n1p2";
        };

        # NOTE: the DRM-card0 race that previously needed a host-side
        # "wait-for-drm-card" initrd gate here is now fixed in the agent
        # itself (luks-controller-unlock ≥ 027ea3e: it poll-retries the
        # ask request until /dev/dri/card0 appears instead of giving up
        # after the first inotify wake). maskConsoleAgent stays false as a
        # keyboard fallback until a run of clean controller-PIN boots is
        # confirmed; re-enable masking then.

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

        # Auto-hibernate after 2h of suspend so the battery doesn't drain
        # flat when the deck is left suspended. The Steam UI's Suspend
        # button calls plain `systemctl suspend` via logind dbus, which
        # ignores HibernateDelaySec (that only fires for
        # suspend-then-hibernate). Workaround: arm an RTC-backed
        # systemd timer when suspend.target activates; WakeSystem=true
        # programs /sys/class/rtc/rtc0/wakealarm so the kernel resumes
        # at the deadline, then the timer fires `systemctl hibernate`.
        # partOf=suspend.target cancels the timer if the user resumes
        # manually before 2h elapses. Requires the swap LV in
        # disko-config to be marked resumeDevice=true.
        systemd.services.auto-hibernate-after-suspend = {
          description = "Hibernate after extended suspend to save battery";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/systemctl hibernate";
          };
        };
        systemd.timers.auto-hibernate-after-suspend = {
          description = "Trigger hibernate after 2h in suspend";
          wantedBy = [ "suspend.target" ];
          partOf = [ "suspend.target" ];
          timerConfig = {
            OnActiveSec = "2h";
            AccuracySec = "1m";
            WakeSystem = true;
            RemainAfterElapse = false;
          };
        };


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
        #
        # The `f` rule's parent dirs MUST be declared explicitly with `d`
        # rules owned by the user. On a fresh impermanence boot /home/ali
        # doesn't exist yet, and systemd-tmpfiles creates the parents of an
        # `f` rule as root by default — which left /home/ali itself
        # root-owned before the user session started. The result:
        # home-manager activation failed ("Could not find suitable profile
        # directory"), the user had no writable home, and no apps/config
        # loaded. tmpfiles processes shorter paths first, so these `d`
        # rules own the chain before the file is created.
        systemd.tmpfiles.rules = [
          "d /home/${username} 0700 ${username} users -"
          "d /home/${username}/.local 0755 ${username} users -"
          "d /home/${username}/.local/share 0755 ${username} users -"
          "d /home/${username}/.local/share/Steam 0755 ${username} users -"
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

        # programs.steam (including extraCompatPackages = proton-ge-bin)
        # comes from modules/desktop.
        #
        # programs.steam.extraCompatPackages only exposes
        # STEAM_EXTRA_COMPAT_TOOLS_PATHS via nixpkgs's `steam-gamescope`
        # wrapper, which Jovian's autostart bypasses (Jovian's
        # steam-launcher.service launches Steam directly under the user
        # systemd manager, which never sources /etc/profile or PAM env).
        # Inject the var directly into the unit's Environment so the
        # Steam process inherits it on launch.
        systemd.user.services.steam-launcher.environment.STEAM_EXTRA_COMPAT_TOOLS_PATHS =
          lib.makeSearchPathOutput "steamcompattool" "" config.programs.steam.extraCompatPackages;

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

        # On-screen keyboard for the Plasma (Wayland) desktop session via
        # Maliit + KWin's input-method-v2. The Steam/"Valve" OSK only
        # exists inside Gaming Mode (gamescope draws it); in a plain Plasma
        # session Maliit is the working VK. This host's Plasma is NOT
        # managed by plasma-manager, so rather than own kwinrc we poke the
        # single `[Wayland] InputMethod` key with kwriteconfig at HM
        # activation (idempotent; takes effect at the next session start).
        # Tap a text field on the touchscreen — or toggle from the system
        # tray "Virtual Keyboard" applet — to raise it.
        home-manager.users.${username} = { lib, pkgs, ... }: {
          home.packages = [ pkgs.maliit-keyboard pkgs.maliit-framework ];
          home.activation.kwinMaliitVk = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
              --file kwinrc --group Wayland --key InputMethod \
              "${pkgs.maliit-keyboard}/share/applications/com.github.maliit.keyboard.desktop"
          '';
        };

        # Stylix theme is configured by the desktop module (gruvbox-dark-medium).

        system.stateVersion = "24.05";

        users.users.ali = {
          isNormalUser = true;
          description = "Alison Jenkins";
          initialPassword = "initPw!";
          extraGroups = [ "networkmanager" "wheel" "docker" "realtime" "input" ];
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

          # Run the Steam client in the background within the Plasma
          # session so the STEAM+X on-screen keyboard is available here
          # too (the Steam OSK only works while the client is alive, and
          # this specialisation keeps Gaming Mode autostart off above).
          # `-silent` starts it minimised to the system tray. Maliit
          # (configured for the base config) remains the no-Steam
          # fallback for early boot / a broken Steam client.
          systemd.user.services.steam-desktop = {
            description = "Steam client (desktop mode) for the STEAM+X on-screen keyboard";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            after = [ "graphical-session.target" ];
            serviceConfig = {
              ExecStart = "${config.programs.steam.package}/bin/steam -silent";
              Restart = "on-failure";
              RestartSec = 5;
            };
          };

          system.nixos.tags = [ "desktop-mode" ];
        };
      })
    ];
  };
}
