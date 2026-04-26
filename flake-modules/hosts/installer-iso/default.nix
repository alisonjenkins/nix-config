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
              gnugrep
              gnused
              jq
              kdePackages.kdialog
              kdePackages.konsole
              util-linux
              nix
            ];
            text = ''
              set -euo pipefail

              REPO=/home/nixos/nix-config
              if [ ! -d "$REPO/.git" ]; then
                kdialog --error "nix-config not found at $REPO. Wait for the clone-nix-config service to finish or clone manually, then retry."
                exit 1
              fi
              cd "$REPO"

              # Discover hosts from the flake. Filter the installer itself
              # and any darwin/home-only configs (those live under
              # darwinConfigurations / homeConfigurations).
              HOSTS=$(nix eval --json .#nixosConfigurations \
                --apply 'cfgs: builtins.attrNames cfgs' 2>/dev/null \
                | jq -r '.[]' \
                | grep -vE '^installer-iso$' \
                | sort)

              if [ -z "$HOSTS" ]; then
                kdialog --error "No installable nixosConfigurations found in $REPO."
                exit 1
              fi

              # Build kdialog --menu argument list: "value" "label" pairs.
              menu_args=()
              while IFS= read -r h; do
                menu_args+=("$h" "$h")
              done <<< "$HOSTS"

              HOST=$(kdialog --title "Install NixOS" \
                --menu "Select host configuration to install:" \
                "''${menu_args[@]}") || exit 0
              [ -n "$HOST" ] || exit 0

              # Build disk picker. lsblk -d lists whole disks only; -e 7,11
              # filters out loop and CD/DVD devices.
              disk_args=()
              while read -r name size model; do
                [ -n "$name" ] || continue
                disk_args+=("/dev/$name" "$size  $model")
              done < <(lsblk -dn -o NAME,SIZE,MODEL -e 7,11)

              if [ ''${#disk_args[@]} -eq 0 ]; then
                kdialog --error "No installable disks detected."
                exit 1
              fi

              DISK=$(kdialog --title "Target disk" \
                --menu "Select target disk for $HOST.\nALL DATA WILL BE ERASED." \
                "''${disk_args[@]}") || exit 0
              [ -n "$DISK" ] || exit 0

              kdialog --warningcontinuecancel \
                "About to ERASE $DISK and install $HOST.\n\nThis cannot be undone. Continue?" \
                || exit 0

              PWD1=$(kdialog --password "LUKS password for disk encryption:") || exit 0
              if [ -z "$PWD1" ]; then
                kdialog --error "Empty password not allowed."
                exit 1
              fi
              PWD2=$(kdialog --password "Confirm LUKS password:") || exit 0
              if [ "$PWD1" != "$PWD2" ]; then
                kdialog --error "Passwords don't match."
                exit 1
              fi

              # Write password to keyfile with NO trailing newline so that
              # cryptsetup matches when the user types it at boot.
              printf '%s' "$PWD1" | sudo tee /tmp/secret.key > /dev/null
              sudo chmod 600 /tmp/secret.key
              unset PWD1 PWD2

              # Hand off to konsole so the user sees disko + nixos-install
              # progress and can read errors. --hold keeps it open after.
              exec konsole --hold -e bash -c "
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
                sudo rm -f /tmp/secret.key
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
