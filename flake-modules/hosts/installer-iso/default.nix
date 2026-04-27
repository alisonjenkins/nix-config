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

          # WiFi auth fix for Steam Deck (and any host where the
          # autologin `nixos` user has no password):
          #   * Put `nixos` in `networkmanager` + `wheel` so polkit
          #     rules grant it NM management without a password prompt.
          #   * Tell NM to store WiFi PSKs as system-owned secrets
          #     (`psk-flags=0`) in /etc/NetworkManager/system-connections
          #     instead of routing them through kwallet — kwallet PAM
          #     auto-unlock can't unlock the wallet for a passwordless
          #     user, which causes plasma-nm to hang at "Waiting for
          #     authorization" after the user types their WiFi password.
          #   * Polkit rule grants any networkmanager-group member full
          #     NM control without auth, as belt-and-braces in case the
          #     distro polkit rules change.
          users.users.nixos.extraGroups = [
            "networkmanager"
            "wheel"
          ];
          networking.networkmanager = {
            enable = true;
            settings.connection-defaults = {
              "802-11-wireless-security.psk-flags" = 0;
              "802-1x.password-flags" = 0;
            };
          };
          security.polkit.extraConfig = ''
            polkit.addRule(function(action, subject) {
              if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0
                  && subject.isInGroup("networkmanager")) {
                return polkit.Result.YES;
              }
            });
          '';

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
            kdePackages.kdialog
            kdePackages.konsole
          ];

          # Allow `sudo` without a password so the installer launcher can
          # run disko + nixos-install non-interactively.
          security.sudo.wheelNeedsPassword = lib.mkForce false;

          # Drop a desktop launcher into the autologin user's Desktop
          # directory pointing at the install-nixos script.
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

          # Plasma 6 refuses to launch untrusted .desktop files. Pre-create
          # the Desktop directory and copy the launcher with executable
          # bit so Plasma renders it as a clickable tile. The user still
          # has to confirm "trust" once on first click.
          systemd.tmpfiles.rules = [
            "d /home/nixos/Desktop 0755 nixos users -"
            "C /home/nixos/Desktop/install-nixos.desktop 0755 nixos users - /etc/skel/Desktop/install-nixos.desktop"
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
