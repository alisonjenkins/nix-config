{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  pkgs = import inputs.nixpkgs {
    inherit system;

    config = {
      allowUnfree = true;
    };

    overlays = [
        self.overlays.additions
        self.overlays.master-packages
        self.overlays.unstable-packages
        self.overlays.zk
        inputs.nur.overlays.default
        inputs.fenix.overlays.default
      ]
      ++ (
        if builtins.getEnv "HOSTNAME" == "steamdeck"
        then [ inputs.nixgl.overlay ]
        else [ ]
      );
  };

  # Valve Steam Frame (SteamOS, aarch64-linux). Home config:
  # home/machines/steam-frame (README.md there has the setup steps).
  framePkgs = import inputs.nixpkgs {
    system = "aarch64-linux";
    config.allowUnfree = true;
    overlays = [
      self.overlays.additions
      self.overlays.master-packages
      self.overlays.unstable-packages
    ];
  };
  # SteamOS's default user on the Frame. steam-frame-nix's installer and
  # `just switch` pick homeConfigurations.<user>, so it must match `id -un`.
  frameUsername = "steamos";

  bluetoothMacs = {
    sonyHeadset = "88:C9:E8:06:5E:9C";
  };
in {
  flake.homeConfigurations = {
    "ali" = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        # home-linux assumes stylix is present — it sets stylix options directly
        # and several of its programs set stylix.targets.*. On NixOS hosts the
        # module arrives via inputs.stylix.nixosModules.stylix (modules/desktop);
        # a standalone home-manager config has to import it itself.
        inputs.stylix.homeModules.stylix
        self.homeModules.home-linux
        self.homeModules.ali-desktop-arch-config
      ];

      extraSpecialArgs = {
        inherit inputs;
        username = "ali";
        hostname = "ali-desktop-arch";
        bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
        # Declared with defaults in home/programs/tmux, but the module system
        # resolves named arguments through _module.args and ignores a lambda
        # default, so they have to be supplied here.
        github_clone_ssh_host_personal = "github.com";
        github_clone_ssh_host_work = "github.com";
        gitUserName = "Alison Jenkins";
        gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
        primarySSHKey = "~/.ssh/id_personal.pub";
        gitGPGSigningKey = "";
      };
    };

    "deck" = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        # See the note on the ali config above.
        inputs.stylix.homeModules.stylix
        self.homeModules.home-linux
        self.homeModules.steam-deck-config
        inputs.nix-index-database.homeModules.nix-index
      ];

      extraSpecialArgs = {
        # No headset paired with this machine. The swayidle module declares this
        # with a "" default, but _module.args resolution ignores lambda
        # defaults, so it has to be given; suspend-resume skips the reconnect
        # when it is empty.
        bluetoothHeadsetMac = "";
        gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
        gitGPGSigningKey = "";
        gitUserName = "Alison Jenkins";
        # See the note on the ali config above.
        github_clone_ssh_host_personal = "github.com";
        github_clone_ssh_host_work = "github.com";
        hostname = "steam-deck";
        inherit inputs;
        primarySSHKey = "~/.ssh/id_personal.pub";
        username = "deck";
      };
    };

    ${frameUsername} = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = framePkgs;

      modules = [
        inputs.steam-frame-nix.homeManagerModules.default
        inputs.nix-index-database.homeModules.nix-index
        # home/programs/{git,ssh} declare sops secrets behind workIdentity, so
        # the option has to exist even though nothing here uses sops.
        inputs.sops-nix.homeManagerModules.sops
        self.homeModules.steam-frame-config
        {
          home = {
            username = frameUsername;
            homeDirectory = "/home/${frameUsername}";
          };
        }
      ];

      extraSpecialArgs = {
        inherit inputs;
        username = frameUsername;
        hostname = "steam-frame";
        gitUserName = "Alison Jenkins";
        gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
        # No 1Password on the headset: commits aren't signed here, and SSH uses
        # the Frame's own key (home/machines/steam-frame/README.md) rather than the agent.
        gitGPGSigningKey = "";
        primarySSHKey = "~/.ssh/id_ed25519";
        sshUse1Password = false;
        # Declared with defaults in home/programs/tmux, but _module.args
        # resolution ignores lambda defaults (see the ali config above).
        github_clone_ssh_host_personal = "github.com";
        github_clone_ssh_host_work = "github.com";
        # home-common normally supplies these as _module.args defaults; this
        # config doesn't import it.
        azureDevopsRsaKey = "";
        enableDifftastic = true;
        workIdentity = false;
        workIdentitySecretsFile = null;
      };
    };
  };
}
