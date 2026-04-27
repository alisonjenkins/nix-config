{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in
{
  flake.nixosConfigurations.installer-iso = lib.nixosSystem {
    specialArgs = {
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }
      "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-base.nix"
      (
        { pkgs, inputs, ... }:
        let
          # disko CLI from the same source revision that produces the
          # nixosModule used by host configs (`inputs.disko`). Using a
          # `nix run github:nix-community/disko` would pull master and
          # risk CLI ↔ module version drift, which surfaces as a
          # spurious "config not found" at install time.
          # disko-install is the all-in-one wrapper that DOES support
          # `--disk NAME DEVICE` for module-style configs (the plain
          # `disko` wrapper does not — only `--argstr`, which needs
          # function-style `diskoConfigurations`). It also performs
          # the nixos-install step itself so we don't need a separate
          # call.
          diskoPkg = inputs.disko.packages.${system}.disko;
          diskoInstallPkg = inputs.disko.packages.${system}.disko-install;
          installNixos = pkgs.writeShellApplication {
            name = "install-nixos";
            runtimeInputs = [
              diskoPkg
              diskoInstallPkg
            ] ++ (with pkgs; [
              coreutils
              gawk
              git
              gnugrep
              gnused
              jq
              kdePackages.kdialog
              kdePackages.konsole
              networkmanager
              util-linux
              nix
            ]);
            text = ''
              set -euo pipefail

              # Tee everything to a log file so the user can read it
              # later if konsole closes or output scrolls off.
              LOG=/tmp/install-nixos.log
              exec > >(tee -a "$LOG") 2>&1

              # Show line numbers in `set -x` traces if we ever flip
              # them on. PS4 is shell-only; harmless when -x is off.
              export PS4='+ [$LINENO] '

              # ERR trap: any unhandled failure under `set -e` prints
              # the failing line + command and pops a kdialog so the
              # user knows WHY install-nixos exited. Konsole's --hold
              # keeps the window open after this trap fires.
              trap 'rc=$?; echo; echo "==> install-nixos ABORTED (exit $rc) at line $LINENO: $BASH_COMMAND" >&2; kdialog --error "install-nixos aborted (exit $rc).\n\nLine $LINENO: $BASH_COMMAND\n\nFull log: $LOG" 2>/dev/null || true; exit $rc' ERR

              # Print a visible banner before each phase so the user
              # always knows what the script is doing.
              step() { echo; echo "==> $*"; echo; }

              echo "==================================================="
              echo " install-nixos starting at $(date -Iseconds)"
              echo " log file: $LOG"
              echo "==================================================="

              REPO=/home/nixos/nix-config
              REPO_URL=https://github.com/alisonjenkins/nix-config.git

              step "Locating nix-config repo at $REPO"
              # Wait for the clone-nix-config service to finish, then fall
              # back to cloning inline so the user doesn't have to drop to
              # a terminal if the boot-time clone failed (e.g. no network
              # at boot).
              while [ ! -d "$REPO/.git" ]; do
                echo "  no repo yet — attempting fresh clone from $REPO_URL"
                if git clone --depth 1 "$REPO_URL" "$REPO"; then
                  continue
                fi
                kdialog --warningyesno \
                  "Failed to clone nix-config into $REPO.\n\nSee terminal / $LOG for details. Check network then click Yes to retry, or No to abort." \
                  || exit 0
                rm -rf "$REPO"
              done
              cd "$REPO"
              echo "  repo present at $REPO ($(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown) on $(git -C "$REPO" branch --show-current 2>/dev/null || echo unknown))"

              step "Asking whether to update nix-config from origin"
              # Offer to pull latest changes from origin. Default to skip
              # so a cached repo "just works" but the user can refresh
              # without rebooting the installer.
              UPDATE_CHOICE=$(kdialog --title "Update nix-config" \
                --menu "Update $REPO from origin before installing?" \
                skip "Use what's already on disk (default)" \
                pull "Fast-forward pull (preserves local edits)" \
                reset "Hard reset to origin/HEAD (DISCARDS local edits)" \
                ) || exit 0
              echo "  user chose: $UPDATE_CHOICE"

              case "$UPDATE_CHOICE" in
                pull)
                  if ! git_out=$(git -C "$REPO" pull --ff-only 2>&1); then
                    kdialog --error "git pull failed:\n\n$git_out"
                    exit 1
                  fi
                  kdialog --passivepopup "$git_out" 5
                  ;;
                reset)
                  kdialog --warningcontinuecancel \
                    "This will discard ALL local edits in $REPO. Continue?" \
                    || exit 0
                  if ! git_out=$( {
                    git -C "$REPO" fetch origin
                    git -C "$REPO" reset --hard origin/HEAD
                    git -C "$REPO" clean -fdx
                  } 2>&1); then
                    kdialog --error "git update failed:\n\n$git_out"
                    exit 1
                  fi
                  kdialog --passivepopup "Reset to origin/HEAD" 5
                  ;;
                skip|*) ;;
              esac

              step "Checking for network connectivity"
              # Internet precheck — nix eval / git pull need network. Loop
              # with a user-friendly prompt rather than letting nix fail
              # with a network error. The user is expected to run the
              # `Connect WiFi` desktop launcher (or use Plasma's NM tray
              # applet) before reaching this point.
              while ! nm-online -t 2 -q 2>/dev/null; do
                echo "  nm-online: no connectivity — prompting user"
                kdialog --warningyesno \
                  "No network connection detected.\n\nUse the Connect WiFi launcher (or NM tray icon) then click Yes to retry. No aborts." \
                  || exit 0
              done
              echo "  network: OK"

              step "Listing host configurations from flake (this can take several minutes on first run while flake inputs download — watch the terminal for progress)"
              # Host picker. Re-evaluate on each loop iteration so the
              # user can edit the flake locally and rescan without
              # restarting the launcher.
              #
              # NOTE: stderr is intentionally NOT captured — it streams
              # live to the terminal so the user can see nix's
              # download/build progress instead of staring at a blank
              # window. Only stdout (the JSON we need) is captured.
              while true; do
                err_log=$(mktemp)
                if HOSTS_JSON=$(nix eval --json .#nixosConfigurations \
                    --apply 'cfgs: builtins.attrNames cfgs' \
                    --print-build-logs \
                    2> >(tee "$err_log" >&2)); then
                  rm -f "$err_log"
                else
                  rc=$?
                  err_tail=$(tail -c 2000 "$err_log")
                  rm -f "$err_log"
                  echo "  nix eval failed (exit $rc)"
                  kdialog --warningyesno \
                    "nix eval failed (exit $rc):\n\n$err_tail\n\nFix the flake then click Yes to retry, or No to abort." \
                    || exit 0
                  continue
                fi
                HOSTS=$(echo "$HOSTS_JSON" | jq -r '.[]' \
                  | grep -vE '^installer-iso$' | sort || true)
                if [ -z "$HOSTS" ]; then
                  echo "  no installable hosts after filtering installer-iso"
                  kdialog --warningyesno \
                    "No installable nixosConfigurations found.\n\nClick Yes to retry, or No to abort." \
                    || exit 0
                  continue
                fi
                echo "  found hosts: $(echo "$HOSTS" | tr '\n' ' ')"

                menu_args=()
                while IFS= read -r h; do
                  menu_args+=("$h" "$h")
                done <<< "$HOSTS"

                HOST=$(kdialog --title "Install NixOS" \
                  --menu "Select host configuration to install:" \
                  "''${menu_args[@]}") || exit 0
                [ -n "$HOST" ] && break
              done
              echo "  selected host: $HOST"

              step "Picking target disk for $HOST"
              # Disk picker with rescan loop — handles late-plugged USB.
              while true; do
                disk_args=()
                while read -r name size model; do
                  [ -n "$name" ] || continue
                  disk_args+=("/dev/$name" "$size  $model")
                done < <(lsblk -dn -o NAME,SIZE,MODEL -e 7,11)

                if [ ''${#disk_args[@]} -eq 0 ]; then
                  kdialog --warningyesno \
                    "No installable disks detected.\n\nPlug a disk in then click Yes to rescan, or No to abort." \
                    || exit 0
                  continue
                fi

                DISK=$(kdialog --title "Target disk" \
                  --menu "Select target disk for $HOST.\nALL DATA WILL BE ERASED." \
                  "''${disk_args[@]}") || exit 0
                [ -n "$DISK" ] && break
              done
              echo "  selected disk: $DISK"

              step "Final confirmation before erasing $DISK"
              kdialog --warningcontinuecancel \
                "About to ERASE $DISK and install $HOST.\n\nThis cannot be undone. Continue?" \
                || exit 0

              step "Collecting LUKS password"
              # LUKS password loop: re-prompt on empty input or mismatch
              # rather than aborting. Cancel button still aborts.
              while true; do
                PWD1=$(kdialog --password "LUKS password for disk encryption:") || exit 0
                if [ -z "$PWD1" ]; then
                  kdialog --sorry "Password cannot be empty. Try again."
                  continue
                fi
                PWD2=$(kdialog --password "Confirm LUKS password:") || exit 0
                if [ "$PWD1" != "$PWD2" ]; then
                  kdialog --sorry "Passwords don't match. Try again."
                  continue
                fi
                break
              done

              # Write password to keyfile with NO trailing newline so that
              # cryptsetup matches when the user types it at boot.
              printf '%s' "$PWD1" | sudo tee /tmp/secret.key > /dev/null
              sudo chmod 600 /tmp/secret.key
              unset PWD1 PWD2

              # We're already running inside konsole (see the desktop
              # launcher's `Exec=konsole --hold -e install-nixos`), so
              # disko + nixos-install can run inline and stream output
              # straight to the user's terminal. Wipe the LUKS keyfile
              # on exit even on failure.
              trap 'sudo rm -f /tmp/secret.key' EXIT

              step "Running disko-install (format $DISK + install $HOST)"
              # disko-install is the right tool for module-style
              # disko configs where we need a runtime --disk
              # override. The plain `disko` wrapper has no --disk
              # flag (only --argstr, which requires a function-style
              # `diskoConfigurations` entry that none of our hosts
              # provide). disko-install also performs the nixos
              # install in the same step, so we don't need a
              # separate `nixos-install` call afterwards.
              sudo disko-install \
                --mode format \
                --flake ".#$HOST" \
                --disk disk1 "$DISK"

              echo
              echo "=========================================="
              echo " Install complete. Press Enter to reboot."
              echo "=========================================="
              read -r _
              sudo reboot
            '';
          };

          # WiFi launcher that bypasses plasma-nm + kwallet entirely.
          # Talks straight to NetworkManager via `nmcli` so there is no
          # secret-agent in the loop — `psk-flags=0` from
          # `connection-defaults` means NM stores the PSK system-wide.
          connectWifi = pkgs.writeShellApplication {
            name = "connect-wifi";
            runtimeInputs = with pkgs; [
              coreutils
              gawk
              gnused
              kdePackages.kdialog
              networkmanager
            ];
            text = ''
              set -euo pipefail

              # Make sure the radio is on. `nmcli radio wifi on` is a
              # no-op if it's already on.
              nmcli radio wifi on >/dev/null 2>&1 || true

              # Force a rescan so freshly-powered radios populate the
              # cache. Some drivers need a couple of seconds.
              nmcli device wifi rescan >/dev/null 2>&1 || true
              sleep 2

              # SSID picker. Loop so the user can rescan without
              # restarting the launcher.
              while true; do
                # SSID may contain spaces, so use a literal tab as the
                # nmcli terse separator. Strip empty / hidden SSIDs.
                mapfile -t lines < <(
                  nmcli -t -s -f IN-USE,SSID,SECURITY,SIGNAL device wifi list \
                    | awk -F: '$2 != "" && !seen[$2]++' \
                    | sort -t: -k4 -nr
                )

                if [ ''${#lines[@]} -eq 0 ]; then
                  kdialog --warningyesnocancel \
                    "No WiFi networks visible.\n\nYes = rescan, No = abort, Cancel = abort." \
                    && { nmcli device wifi rescan >/dev/null 2>&1 || true; sleep 2; continue; }
                  exit 0
                fi

                menu_args=("__rescan__" "[ Rescan networks ]")
                while IFS=: read -r in_use ssid sec signal; do
                  [ -n "$ssid" ] || continue
                  marker=" "
                  [ "$in_use" = "*" ] && marker="*"
                  menu_args+=("$ssid" "$marker $ssid  ($sec, $signal%)")
                done < <(printf '%s\n' "''${lines[@]}")

                SSID=$(kdialog --title "Connect WiFi" \
                  --menu "Select a network:" \
                  "''${menu_args[@]}") || exit 0

                if [ "$SSID" = "__rescan__" ]; then
                  nmcli device wifi rescan >/dev/null 2>&1 || true
                  sleep 2
                  continue
                fi
                break
              done

              # If the connection already exists (e.g. from a previous
              # successful connect), bring it up without re-prompting
              # for the password.
              if nmcli -t -f NAME connection show | grep -Fxq "$SSID"; then
                if up_out=$(nmcli connection up id "$SSID" 2>&1); then
                  kdialog --passivepopup "Reconnected to $SSID" 5
                  exit 0
                fi
                kdialog --sorry "Reconnect failed:\n\n$up_out\n\nWill prompt for password and re-create the connection."
                nmcli connection delete id "$SSID" >/dev/null 2>&1 || true
              fi

              # Password loop: re-prompt on empty input.
              while true; do
                PSK=$(kdialog --password "Password for \"$SSID\":") || exit 0
                if [ -z "$PSK" ]; then
                  kdialog --sorry "Password cannot be empty. Try again."
                  continue
                fi
                break
              done

              # Connect. nmcli writes the connection profile and
              # respects `[connection-defaults] psk-flags=0` so the PSK
              # lands in /etc/NetworkManager/system-connections, not in
              # any user secret store.
              if out=$(nmcli device wifi connect "$SSID" password "$PSK" 2>&1); then
                kdialog --passivepopup "Connected to $SSID" 5
              else
                kdialog --error "Connect failed:\n\n$out"
                exit 1
              fi
            '';
          };
        in
        {
          services.desktopManager.plasma6.enable = true;
          services.displayManager = {
            sddm.enable = true;
            sddm.wayland.enable = true;
            autoLogin = {
              enable = true;
              user = "nixos";
            };
            defaultSession = "plasma";
          };
          networking.hostName = "nixos-installer";

          # Use the latest mainline kernel so disko can format btrfs
          # with `compress=zstd:-1` (negative zstd levels require
          # kernel ≥ 6.15). nixpkgs' default LTS kernel is currently
          # 6.12.x which would reject the mount option.
          boot.kernelPackages = pkgs.linuxPackages_latest;

          # ZFS is marked broken on the latest kernel (no upstream
          # release tracking 7.x yet) and the installer doesn't need
          # it — drop ZFS from supportedFilesystems and skip building
          # the broken zfs-kernel module.
          boot.supportedFilesystems.zfs = lib.mkForce false;

          # NetworkManager: store WiFi PSKs as system-owned secrets
          # (`psk-flags=0`) in /etc/NetworkManager/system-connections
          # instead of in kwallet. The autologin `nixos` user has no
          # login password so kwallet's PAM auto-unlock can't open the
          # wallet, which causes plasma-nm to hang at "Waiting for
          # authorization" after credentials are entered. The
          # `connect-wifi` desktop launcher below is the recommended
          # path — it talks to NM directly via `nmcli` and bypasses
          # plasma-nm + kwallet entirely.
          # `installation-cd-graphical-base.nix` already enables NM and
          # `installation-device.nix` already adds the `nixos` user to
          # the `networkmanager`/`wheel` groups, so no extra user or
          # polkit config is required here.
          networking.networkmanager.settings.connection-defaults = {
            "802-11-wireless-security.psk-flags" = 0;
            "802-1x.password-flags" = 0;
          };

          # Timezone: pinned to Europe/London so KDE's clock shows the
          # right time out of the box. `timesyncd` is the NixOS default
          # but we set it explicitly so KDE finds an active NTP backend
          # without needing to toggle anything (the toggle was failing
          # with "file is read only" on the ROM-mounted ISO).
          time.timeZone = "Europe/London";
          services.timesyncd.enable = true;

          # On-screen keyboard for Steam Deck / touch installs.
          # InputMethod must be the absolute path to the .desktop file;
          # nixpkgs ships it as com.github.maliit.keyboard.desktop.
          # KWIN_IM_SHOW_ALWAYS=1 makes the OSK pop on focus for mouse/touch
          # both — without it KWin only auto-shows on touch events.
          environment.etc."xdg/kwinrc".text = ''
            [Wayland]
            VirtualKeyboardEnabled=true
            InputMethod=${pkgs.maliit-keyboard}/share/applications/com.github.maliit.keyboard.desktop
          '';
          environment.sessionVariables.KWIN_IM_SHOW_ALWAYS = "1";

          nix.settings = {
            experimental-features = [
              "nix-command"
              "flakes"
              "ca-derivations"
            ];
            trusted-users = [
              "root"
              "@wheel"
              "nixos"
            ];
          };

          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
              PermitRootLogin = "prohibit-password";
            };
          };

          users.users.nixos.openssh.authorizedKeys.keys = outputs.lib.sshKeys.all;
          users.users.root.openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];

          environment.systemPackages = [
            diskoPkg
            diskoInstallPkg
          ] ++ (with pkgs; [
            git
            vim
            just
            maliit-keyboard
            installNixos
            connectWifi
            kdePackages.kdialog
            kdePackages.konsole
          ]);

          # Allow `sudo` without a password so the installer launcher can
          # run disko + nixos-install non-interactively.
          security.sudo.wheelNeedsPassword = lib.mkForce false;

          # Drop desktop launchers into the autologin user's Desktop
          # directory pointing at the install-nixos and connect-wifi
          # scripts.
          environment.etc."skel/Desktop/install-nixos.desktop" = {
            mode = "0755";
            text = ''
              [Desktop Entry]
              Type=Application
              Name=Install NixOS
              Comment=Run the NixOS installer for this flake
              Icon=system-software-install
              Exec=${pkgs.kdePackages.konsole}/bin/konsole --hold -e ${installNixos}/bin/install-nixos
              Terminal=false
              Categories=System;
            '';
          };
          environment.etc."skel/Desktop/connect-wifi.desktop" = {
            mode = "0755";
            text = ''
              [Desktop Entry]
              Type=Application
              Name=Connect WiFi
              Comment=Pick a WiFi network and connect via nmcli
              Icon=network-wireless
              Exec=${connectWifi}/bin/connect-wifi
              Terminal=false
              Categories=System;Network;
            '';
          };

          # Plasma 6 refuses to launch untrusted .desktop files. Pre-create
          # the Desktop directory and copy the launchers with executable
          # bit so Plasma renders them as clickable tiles. The user still
          # has to confirm "trust" once on first click.
          systemd.tmpfiles.rules = [
            "d /home/nixos/Desktop 0755 nixos users -"
            "C /home/nixos/Desktop/install-nixos.desktop 0755 nixos users - /etc/skel/Desktop/install-nixos.desktop"
            "C /home/nixos/Desktop/connect-wifi.desktop 0755 nixos users - /etc/skel/Desktop/connect-wifi.desktop"
          ];

          systemd.services.clone-nix-config = {
            description = "Clone nix-config and pre-fetch flake inputs on boot";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [
              pkgs.git
              pkgs.openssh
              pkgs.cacert
              pkgs.nix
            ];
            serviceConfig = {
              Type = "oneshot";
              User = "nixos";
              Group = "users";
              WorkingDirectory = "/home/nixos";
              # Drop ConditionPathExists so re-runs (after a manual rm)
              # still pre-warm. If the repo exists we just skip the
              # clone step inline.
              Environment = [
                "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "HOME=/home/nixos"
                "NIX_CONFIG=experimental-features = nix-command flakes"
              ];
            };
            script = ''
              if [ ! -d /home/nixos/nix-config/.git ]; then
                git clone --depth 1 https://github.com/alisonjenkins/nix-config.git /home/nixos/nix-config
              fi
              # Pre-fetch flake inputs so the user-facing install-nixos
              # eval is near-instant. Non-fatal — a network blip just
              # means the user pays the fetch cost during install.
              cd /home/nixos/nix-config
              nix flake archive --json >/dev/null 2>&1 || true
            '';
          };

          image.fileName = lib.mkForce "nixos-installer-custom-${system}.iso";
        }
      )
    ];
  };
}
