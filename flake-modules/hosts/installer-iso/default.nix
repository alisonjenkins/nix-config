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
        { pkgs, ... }:
        let
          installNixos = pkgs.writeShellApplication {
            name = "install-nixos";
            runtimeInputs = with pkgs; [
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
            ];
            text = ''
              set -euo pipefail

              REPO=/home/nixos/nix-config
              REPO_URL=https://github.com/alisonjenkins/nix-config.git

              # Wait for the clone-nix-config service to finish, then fall
              # back to cloning inline so the user doesn't have to drop to
              # a terminal if the boot-time clone failed (e.g. no network
              # at boot).
              while [ ! -d "$REPO/.git" ]; do
                if clone_out=$(git clone --depth 1 "$REPO_URL" "$REPO" 2>&1); then
                  continue
                fi
                kdialog --warningyesno \
                  "Failed to clone nix-config into $REPO:\n\n$clone_out\n\nCheck network then click Yes to retry, or No to abort." \
                  || exit 0
                rm -rf "$REPO"
              done
              cd "$REPO"

              # Offer to pull latest changes from origin. Default to skip
              # so a cached repo "just works" but the user can refresh
              # without rebooting the installer.
              UPDATE_CHOICE=$(kdialog --title "Update nix-config" \
                --menu "Update $REPO from origin before installing?" \
                skip "Use what's already on disk (default)" \
                pull "Fast-forward pull (preserves local edits)" \
                reset "Hard reset to origin/HEAD (DISCARDS local edits)" \
                ) || exit 0

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

              # Internet precheck — nix eval / git pull need network. Loop
              # with a user-friendly prompt rather than letting nix fail
              # with a network error. The user is expected to use Plasma's
              # NetworkManager applet in the system tray to connect WiFi.
              while ! nm-online -t 2 -q 2>/dev/null; do
                kdialog --warningyesno \
                  "No network connection detected.\n\nOpen the NetworkManager icon in the system tray to connect to WiFi, then click Yes to retry. Click No to abort." \
                  || exit 0
              done

              # Host picker. Re-evaluate on each loop iteration so the
              # user can edit the flake locally and rescan without
              # restarting the launcher.
              while true; do
                HOSTS_JSON=$(nix eval --json .#nixosConfigurations \
                  --apply 'cfgs: builtins.attrNames cfgs' 2>&1) || {
                  kdialog --warningyesno \
                    "nix eval failed:\n\n$HOSTS_JSON\n\nFix the flake then click Yes to retry, or No to abort." \
                    || exit 0
                  continue
                }
                HOSTS=$(echo "$HOSTS_JSON" | jq -r '.[]' \
                  | grep -vE '^installer-iso$' | sort)
                if [ -z "$HOSTS" ]; then
                  kdialog --warningyesno \
                    "No installable nixosConfigurations found.\n\nClick Yes to retry, or No to abort." \
                    || exit 0
                  continue
                fi

                menu_args=()
                while IFS= read -r h; do
                  menu_args+=("$h" "$h")
                done <<< "$HOSTS"

                HOST=$(kdialog --title "Install NixOS" \
                  --menu "Select host configuration to install:" \
                  "''${menu_args[@]}") || exit 0
                [ -n "$HOST" ] && break
              done

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

              kdialog --warningcontinuecancel \
                "About to ERASE $DISK and install $HOST.\n\nThis cannot be undone. Continue?" \
                || exit 0

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

              # Hand off to konsole so the user sees disko + nixos-install
              # progress and can read errors. --hold keeps it open after.
              # Trap inside the inner shell ensures the keyfile is wiped
              # even if disko or nixos-install fails partway through.
              exec konsole --hold -e bash -c "
                trap 'sudo rm -f /tmp/secret.key' EXIT
                set -e
                cd '$REPO'
                echo '==> Running disko (format + mount $DISK)'
                sudo nix run --extra-experimental-features 'nix-command flakes' \
                  github:nix-community/disko -- \
                  --mode disko --flake '.#$HOST' \
                  --arg disk '\"$DISK\"' \
                  --disk disk1 '$DISK'
                echo
                echo '==> Running nixos-install'
                sudo nixos-install --flake '.#$HOST' --no-root-passwd --root /mnt
                echo
                echo '=========================================='
                echo 'Install complete. Press Enter to reboot.'
                echo '=========================================='
                read -r _
                sudo reboot
              "
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

          environment.systemPackages = with pkgs; [
            git
            vim
            just
            maliit-keyboard
            installNixos
            connectWifi
            kdePackages.kdialog
            kdePackages.konsole
          ];

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
              Exec=${installNixos}/bin/install-nixos
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
            description = "Clone nix-config on boot for convenience";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [
              pkgs.git
              pkgs.openssh
              pkgs.cacert
            ];
            serviceConfig = {
              Type = "oneshot";
              User = "nixos";
              Group = "users";
              WorkingDirectory = "/home/nixos";
              ConditionPathExists = "!/home/nixos/nix-config";
              Environment = [
                "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "HOME=/home/nixos"
              ];
            };
            script = ''
              git clone --depth 1 https://github.com/alisonjenkins/nix-config.git /home/nixos/nix-config
            '';
          };

          image.fileName = lib.mkForce "nixos-installer-custom-${system}.iso";
        }
      )
    ];
  };
}
