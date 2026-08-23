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
      # Imported for its Plasma-session fixes, which key off
      # `services.desktopManager.plasma6.enable` (set directly below). The
      # module's own `modules.desktop-wm-plasma6.enable` stays off: it would
      # set displayManager.defaultSession = "plasma", and this host must log
      # straight into Jovian's Gaming Mode instead.
      self.nixosModules.desktop-wm-plasma6
      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.locale
      self.nixosModules.luks-controller-unlock
      self.nixosModules.initrd-ssh
      self.nixosModules.emulation

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.jovian-nixos.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default

      # jovian-nixos sets zramSwap.memoryPercent=50 and base sets 100, both at
      # normal priority → module-system eval conflict (surfaced by deploy-rs's
      # flake checks). Force the Jovian intent (50) to resolve it.
      { zramSwap.memoryPercent = lib.mkForce 50; }

      # nixpkgs 26.11 marks pnpm 9.15.9 insecure. Jovian's decky-loader
      # build pins that pnpm to assemble Decky's static frontend — a
      # build-time-only tool that runs in the nix sandbox and never lands
      # in the runtime closure, so the advisory doesn't reach the running
      # system. Permit it here so this host still evaluates on 26.11.
      { nixpkgs.config.permittedInsecurePackages = [ "pnpm-9.15.9" ]; }

      # Home-manager configuration
      ({ lib, pkgs, ... }: {
        # Must be a single executable: home-manager word-splits
        # $HOME_MANAGER_BACKUP_COMMAND and appends the target as $1.
        home-manager.backupCommand = lib.getExe pkgs.hm-backup-file;
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
      })

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
      ({ config, lib, outputs, pkgs, username, ... }:
      let
        # Exit 0 on battery, 1 while any mains supply is online.
        #
        # Globs every power_supply rather than hardcoding ACAD: the Deck's
        # dock/USB-C PD supplies show up under their own names, and charging
        # over any of them counts as plugged in.
        onBattery = pkgs.writeShellApplication {
          name = "deck-on-battery";
          text = ''
            for supply in /sys/class/power_supply/*; do
              [ -r "$supply/type" ] || continue
              [ "$(cat "$supply/type")" = "Mains" ] || continue
              if [ "$(cat "$supply/online" 2>/dev/null || echo 0)" = "1" ]; then
                exit 1
              fi
            done
          '';
        };
      in {
        # deploy-rs wraps the system profile in an `activatable-nixos-system`
        # layer, adding a symlink hop. jovian-stubs' steamos-update compares
        # `readlink /run/booted-system/kernel` vs `readlink
        # /nix/var/nix/profiles/system/kernel` shallowly, so that wrapper
        # makes the strings differ even when they resolve to the same kernel
        # → the stub returns 8 ("reboot needed") forever and Steam's
        # first-run OOBE loops on "update & restart". Resolve fully
        # (readlink -f) so it compares real kernels (exit 7 = no update).
        # mkOrder 2000 forces this AFTER Jovian's own overlay (which
        # re-defines jovian-stubs and otherwise clobbers a plain/mkAfter
        # override); it reaches steamos-manager + Steam's FHS, both built
        # with final.jovian-stubs.
        nixpkgs.overlays = lib.mkOrder 2000 [
          (_final: prev: {
            jovian-stubs = prev.jovian-stubs.overrideAttrs (old: {
              # NB: jovian-stubs uses `buildCommand`, which bypasses the
              # postInstall hook — the patch must be appended to
              # buildCommand. steamos-update and holo-update are the same
              # source file, installed to two paths (Jovian now drops
              # steamos-update under bin/steamos-polkit-helpers/); patch
              # both. `readlink -f` resolves through deploy-rs's activatable
              # wrapper so the kernel comparison matches and the stub
              # returns 7 instead of 8.
              buildCommand = old.buildCommand + ''
                substituteInPlace \
                  "$out/bin/holo-update" \
                  "$out/bin/steamos-polkit-helpers/steamos-update" \
                  --replace-fail 'readlink /run' 'readlink -f /run' \
                  --replace-fail 'readlink /nix' 'readlink -f /nix'
              '';
            });
          })
          (final: prev:
            # nixos-26.05's gamescope 3.16.24 ships a stale shaders-path.patch
            # — its hunk targets the removed `GetUsrDir` in
            # reshade_effect_manager.cpp (upstream moved that path logic to
            # Utils/DirHelpers.cpp), so patchPhase dies on a failed hunk.
            # nixos-unstable carries the same 3.16.24 src with the corrected
            # patch set + postPatch, so graft those onto 26.05's build (keeping
            # 26.05's deps — aliasing wholesale to unstable.gamescope would drag
            # in a separately-broken unstable 32-bit xwayland). Applied to both
            # the native build and pkgsi686Linux (Steam gaming mode pulls the
            # 32-bit gamescope into hardware.graphics). Drop once 26.05 fixes
            # the patch (or reverts gamescope to 3.16.23).
            #
            # 3.16.24 also adds a tests/ subdir (needs catch2 + leaks a vulkan
            # include-path gap in the test target). Tests aren't run here
            # (doCheck = false), so just disable them via meson — keeps the
            # graft arch-independent (no per-arch catch2) and dodges the test
            # compile break.
            let
              fixGamescope = baseGs: baseGs.overrideAttrs (old: {
                inherit (final.unstable.gamescope) patches postPatch;
                mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Denable_tests=false" ];
              });
            in {
              gamescope = fixGamescope prev.gamescope;
              # gamescope-wsi is a separate instantiation of the same broken
              # package.nix (nixpkgs callPackages it fresh; Jovian re-derives it
              # via `gamescope.override`, which discards .overrideAttrs) — so it
              # needs the same graft applied directly. Steam pulls it into
              # hardware.graphics extraPackages{,32} for the Vulkan WSI layer.
              gamescope-wsi = fixGamescope prev.gamescope-wsi;
              pkgsi686Linux = prev.pkgsi686Linux.extend (_f: p: {
                gamescope = fixGamescope p.gamescope;
                gamescope-wsi = fixGamescope p.gamescope-wsi;
              });
            })
        ];

        modules.base = {
          enable = true;
          bootLoader = "grub";
          enableImpermanence = true;
          impermanencePersistencePath = "/persistence";
          enableCachyOSKernel = false;
          # No btrfs after the XFS migration — beesd is btrfs-only.

          # Hibernate via a real power-off (S5) rather than ACPI S4.
          #
          # With the default "platform" mode the kernel writes the image and
          # then hands the power-down to the firmware's S4 hooks, leaving the
          # Deck in a firmware-managed state whose wake sources the EC picks.
          # Valve doesn't support hibernation, so that path is essentially
          # untested on this hardware: after auto-hibernate the power button
          # does nothing and only attaching USB-C (a PD event the EC always
          # wakes on) brings the Deck back, with the battery still charged.
          # "shutdown" skips the firmware hooks entirely, so resuming is an
          # ordinary power-on — the same path that works from a normal
          # shutdown — and the initrd resume picks the image back up.
          hibernateMode = "shutdown";
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

        # Built-in-speaker audio underruns under demanding games: the 15 W APU
        # downclocks the CPU when the GPU is maxed, so the RT audio thread can't
        # refill a small buffer in time → crackle. Pin a larger fixed quantum
        # (~21 ms @ 48 kHz) so apps/Wine can't negotiate a tiny buffer the
        # throttled APU can't service. Inaudible latency for gaming; mirrors
        # SteamOS's larger-buffer approach. Desktop keeps the 256 default.
        modules.desktop.pipewire = {
          quantum = 1024;
          minQuantum = null; # null => fixed quantum (collapses to `quantum`)
          maxQuantum = null; # fixed
          alsaHeadroom = 2048; # extra DMA slack under load (default 1024)
        };

        modules.desktop-1password.enable = true;
        modules.desktop-aws-tools.enable = true;
        modules.desktop-base.enable = true;
        modules.desktop-kubernetes.enable = true;
        modules.desktop-media.enable = true;
        modules.locale.enable = true;

        # EmuDeck-equivalent emulation stack (modules/emulation). Initial set:
        # NES, SNES, N64, Game Boy, GameCube, Wii U, Switch. Each platform
        # installs its default emulator(s) (NES/SNES/N64/GB via RetroArch cores,
        # GameCube via dolphin-emu, Wii U via cemu, Switch via citron) + the
        # EmuDeck control schemes for the supported standalone emulators.
        #
        # `games` left empty for now: ROMs live in a private B2 bucket that
        # isn't set up yet. content sync is therefore NOT enabled — flip
        # content.enable + provision the sops B2 creds once the bucket exists
        # (see modules/emulation/content.nix + CLAUDE.md "emulation follow-ups").
        # Switch additionally needs prod.keys/title.keys + firmware (own dumps)
        # placed via a content set before games run.
        modules.emulation = {
          enable = true;
          # Animated gaming-mode picker (the single Steam shortcut → one Steam
          # Input layout for the whole stack). Collections are derived from the
          # enabled platforms; wheels are empty until `games` are populated.
          frontend = "retrofe";
          # Out-of-the-box input: RetroArch unified hotkeys (NES/SNES/N64/GB
          # cores) + EmuDeck's curated standalone schemes for the supported
          # emulators in this set (GameCube/Dolphin). emudeckStandaloneDefaults
          # defaults on; Cemu/citron have no shipped scheme yet (Steam Input).
          controls = {
            enable = true;
            retroarch.enable = true;
          };
          platforms = {
            nes.enable = true;
            snes.enable = true;
            n64.enable = true;
            gb.enable = true; # original Game Boy; gbc (Color) is a separate platform
            gamecube.enable = true;
            wiiu.enable = true;
            switch.enable = true;
          };
        };

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

        # Auto-hibernate after 4h of suspend so the battery doesn't drain
        # flat when the deck is left suspended (e.g. in a bag). Both the
        # Steam UI Suspend button and KDE powerdevil call plain `suspend`
        # via logind's dbus Suspend() method, which bypasses
        # HandleSuspendKey/HandleLidSwitch *and* HibernateDelaySec (the
        # latter only fires for the suspend-then-hibernate operation).
        # Workaround: arm an RTC-backed systemd timer when suspend.target
        # activates; WakeSystem=true programs /sys/class/rtc/rtc0/wakealarm
        # so the kernel resumes at the deadline, then the timer fires
        # `systemctl hibernate`. partOf=suspend.target cancels the timer if
        # the user resumes manually first. Requires the swap LV in
        # disko-config to be marked resumeDevice=true (it is).
        #
        # 4h balances quick-resume (put-downs stay in S3, where waking is
        # instant and doesn't need the LUKS controller-PIN dance) against
        # bag-safety: the Deck's S3 draws a few %/hr, so a full charge
        # survives a 4h window comfortably.
        #
        # On AC the hibernation is pointless — nothing is draining — but the
        # alarm is still armed, because the power state can change while the
        # Deck is asleep and nothing on a suspended machine can observe that:
        # in S3 the CPU is halted, so a udev rule on power_supply `online`
        # only ever runs *after* something else has already woken the system.
        # The RTC alarm is that something else. Each wake therefore re-checks
        # the power source and either hibernates (on battery) or goes straight
        # back to suspend (on AC), which re-arms the alarm for the next check.
        #
        # Net effect: unplugging a suspended, plugged-in Deck — putting it in
        # a bag — is picked up within one interval and hibernates as it would
        # have on battery, at the cost of a brief wake every 4h while it sits
        # asleep on the charger.
        systemd.services.auto-hibernate-after-suspend = {
          description = "Hibernate an extended suspend, or re-check later if on AC";
          serviceConfig = {
            Type = "oneshot";
            # NB: `systemctl hibernate` returns as soon as logind queues the
            # job, ~24s before the kernel actually attempts the image write,
            # so its exit status says nothing about whether hibernation
            # worked. Failure is handled by the OnFailure hook on
            # systemd-hibernate.service below, which is the unit that does
            # report a real result.
            ExecStart = lib.getExe (pkgs.writeShellApplication {
              name = "deck-suspend-escalate";
              runtimeInputs = [ pkgs.systemd ];
              text = ''
                if ${lib.getExe onBattery}; then
                  systemctl hibernate
                else
                  # Still on mains: nothing to save, so drop back into S3.
                  # Re-entering suspend.target re-arms the timer, so the power
                  # source is checked again one interval from now. The settle
                  # delay mirrors hibernate-fallback-suspend below: systemd-sleep
                  # has only just thawed user.slice on this wake.
                  sleep 5
                  systemctl suspend
                fi
              '';
            });
          };
        };

        # Hibernation on this hardware is intermittent: roughly half of all
        # attempts abort with
        #   amdgpu 0000:04:00.0: PM: dpm_run_callback(): pci_pm_thaw returns -16
        #   PM: Image saving failed: -11
        #   systemd-sleep: Failed to put system to sleep. System resumed again
        # The snapshot is built fine and then amdgpu refuses to thaw after the
        # ASIC reset that amdgpu_pmops_freeze() performs, so the write is
        # abandoned at 0%. Measured across 8 attempts on 2026-08-12 it was
        # independent of GPU load, of whether an S3 resume preceded it, and of
        # how long the Deck had been awake — i.e. a driver race, not something
        # the timing here can avoid.
        #
        # What must not happen is the Deck being left awake with the screen
        # off: the RTC alarm has already woken it, its timer has elapsed
        # (RemainAfterElapse=false) and suspend.target is inactive, so nothing
        # else puts it back to sleep and the battery runs flat in a bag. A
        # flat Deck ignores the power button entirely until USB-C is attached,
        # which is exactly the failure this whole exercise started from.
        #
        # Falling back to suspend keeps the cost at S3 drain, and because
        # re-entering suspend.target re-arms the timer above, the next attempt
        # follows automatically one interval later — a natural retry loop for
        # a race that succeeds about half the time.
        systemd.services.systemd-hibernate = {
          overrideStrategy = "asDropin";
          unitConfig.OnFailure = "hibernate-fallback-suspend.service";
        };

        systemd.services.hibernate-fallback-suspend = {
          description = "Suspend after a failed hibernation attempt";
          serviceConfig = {
            Type = "oneshot";
            # Let the resume settle before asking for another sleep
            # transition; systemd-sleep has only just thawed user.slice.
            ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
            ExecStart = "${pkgs.systemd}/bin/systemctl suspend";
          };
        };
        systemd.timers.auto-hibernate-after-suspend = {
          description = "Trigger hibernate after 4h in suspend";
          # Armed on every suspend regardless of power source — the service it
          # triggers is what decides between hibernating and going back to
          # sleep. partOf cancels it when the user resumes manually.
          wantedBy = [ "suspend.target" ];
          partOf = [ "suspend.target" ];
          timerConfig = {
            OnActiveSec = "4h";
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

        # Gaming Mode leaves the systemd/D-Bus user environment advertising
        # XDG_SESSION_TYPE=x11 while gamescope-session deliberately runs
        # `systemctl --user unset-environment DISPLAY XAUTHORITY` (removing
        # DISPLAY breaks gamescope startup otherwise). Any D-Bus-activated Qt
        # program therefore selects the xcb QPA plugin, finds no display, and
        # calls qFatal():
        #
        #   kwalletd6: could not connect to display
        #   kwalletd6: Could not load the Qt platform plugin "xcb" ...
        #
        # kwalletd6 is activated repeatedly (Steam's secret storage), so it
        # crash-loops; each abort is picked up by drkonqi, which is itself a
        # Qt GUI program and aborts the same way, and *its* core dump
        # re-triggers drkonqi — a self-amplifying loop that produced 1171
        # core dumps and a load average of ~6 one minute after boot.
        #
        # Give those programs a QPA fallback chain instead. Qt tries the
        # entries in order, so a real Wayland session still gets a window and
        # a headless activation quietly lands on "offscreen" rather than
        # dying. WAYLAND_DISPLAY is deliberately NOT set here: gamescope is
        # started with no explicit backend, so a WAYLAND_DISPLAY in the
        # session environment would make it nest inside itself.
        systemd.user.services.gamescope-qt-platform-env = {
          description = "Usable Qt QPA platform for D-Bus-activated apps in Gaming Mode";
          wantedBy = [ "gamescope-session.service" ];
          before = [ "gamescope-session.service" ];
          after = [ "dbus.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = [
              "${pkgs.systemd}/bin/systemctl --user set-environment 'QT_QPA_PLATFORM=wayland;offscreen'"
              "${pkgs.dbus}/bin/dbus-update-activation-environment --systemd QT_QPA_PLATFORM"
            ];
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

        # Stylix theme is configured by the desktop module (gruvbox-dark-medium).

        system.stateVersion = "24.05";

        users.users.ali = {
          isNormalUser = true;
          description = "Alison Jenkins";
          initialPassword = "initPw!";
          extraGroups = [ "networkmanager" "wheel" "docker" "realtime" "input" ];
          openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];
          packages = with pkgs; [
            # citron is now installed by modules.emulation (switch platform)
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
          # `-silent` starts it minimised to the system tray. NB: until
          # Steam finishes launching (~tens of seconds on first boot)
          # there is no OSK in this session — relevant if you ever need to
          # type before Steam is up.
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
