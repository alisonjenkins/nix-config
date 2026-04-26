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
