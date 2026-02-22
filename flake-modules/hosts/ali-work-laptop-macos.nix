{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
  username = "ajenkins";
  darwinSystem = "aarch64-darwin";

  darwinPkgs = import inputs.nixpkgs_stable_darwin {
    system = darwinSystem;

    config = {
      allowUnfree = true;
    };

    overlays =
      let overlays = import ../../overlays { inherit inputs; };
      in [
        overlays.additions
        overlays.lqx-pin-packages
        overlays.master-packages
        overlays.unstable-packages
        overlays.tmux-sessionizer
        overlays.zk
        inputs.nur.overlays.default
        inputs.rust-overlay.overlays.default
        (self: super: {
          nodejs = super.unstable.nodejs;
        })
      ];
  };

  commonArgs = {
    inherit inputs outputs;
    pkgs = darwinPkgs;
    system = darwinSystem;
    inherit username;
  };

  hostnames = {
    civica = "Alisons-MacBook-Pro";
  };
in {
  flake.darwinConfigurations."${hostnames.civica}" = inputs.darwin.lib.darwinSystem {
    system = darwinSystem;
    modules = [
      ../../hosts/ali-work-laptop-macos/configuration.nix
      inputs.home-manager.darwinModules.home-manager
      {
        # Use timestamp-based backups to prevent conflicts
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${username} = import ../../home/home-macos.nix;
        home-manager.extraSpecialArgs = commonArgs // {
          gitEmail = "alison.jenkins@civica.com";
          gitGPGSigningKey = "~/.ssh/id_civica.pub";
          gitUserName = "Alison Jenkins";
          github_clone_ssh_host_personal = "pgithub.com";
          github_clone_ssh_host_work = "github.com";
          hostname = "${hostnames.civica}";
          primarySSHKey = "~/.ssh/id_civica.pub";
        };
      }
    ];
    specialArgs = commonArgs // {
      hostname = "${hostnames.civica}";
    };
  };
}
