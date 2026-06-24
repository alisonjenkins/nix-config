# home-macos-builder-1 — Mac mini M4 (24GB/256GB), headless aarch64-darwin
# build machine. Acts as a remote Nix builder for the NixOS fleet (see
# modules/darwin-remote-builder) and, later, a GitHub Actions runner.
#
# SCAFFOLD — modelled on ali-mba but stripped of GUI apps. Fill the
# PLACEHOLDER values once the mini is set up:
#   * confirm hostname (home-macos-builder-1)
#   * authorize each NixOS host's /root/.ssh/id_remote_builder.pub on user `ali`
#     (see flake.lib.sshKeys.remoteBuilders in flake-modules/lib.nix)
#   * sops age key on the mini for niks3 / runner token (deferred)
{ inputs, self, ... }:
let
  inherit (self) outputs;
  username = "ali";
  darwinSystem = "aarch64-darwin";

  darwinPkgs = import inputs.nixpkgs {
    system = darwinSystem;
    config.allowUnfree = true;
    overlays = [
      self.overlays.additions
      self.overlays.modifications
      self.overlays.lqx-pin-packages
      self.overlays.master-packages
      self.overlays.unstable-packages
      self.overlays.tmux-sessionizer
      self.overlays.zk
      inputs.nur.overlays.default
      inputs.fenix.overlays.default
    ];
  };

  commonArgs = {
    inherit inputs outputs;
    pkgs = darwinPkgs;
    inherit username;
  };

  hostname = "home-macos-builder-1";
in {
  flake.darwinConfigurations.home-macos-builder-1 = inputs.darwin.lib.darwinSystem {
    system = darwinSystem;
    modules = [
      ({ pkgs, username, hostname, ... }: {
        # Lean toolset for a headless builder — no GUI casks.
        environment.systemPackages = with pkgs; [
          bat
          btop
          cachix
          direnv
          fd
          gh
          git
          htop
          jq
          just
          nix-fast-build
          inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.nvim
          ripgrep
          tmux
          wget
          zoxide
        ];

        networking = {
          hostName = hostname;
          localHostName = hostname;
        };

        nix = {
          enable = true;
          # The mini RECEIVES builds; it doesn't need distributedBuilds itself
          # unless we later chain it to the linux-builder. Left off for now.
          settings = {
            builders-use-substitutes = true;
            download-buffer-size = 256 * 1024 * 1024;
            experimental-features = "nix-command flakes";
            extra-trusted-users = "${username}";
            # Reuse the fleet's substituters so the builder pulls cached deps
            # rather than rebuilding from scratch.
            substituters = [
              "https://cache.nixcache.org"
              "https://cache.nixos.org"
              "https://nix-community.cachix.org"
              "https://fenix.cachix.org"
              "https://nix-darwin.cachix.org"
              "https://devenv.cachix.org"
              "https://deploy-rs.cachix.org"
              "https://crane.cachix.org"
              "https://numtide.cachix.org"
              "https://hercules-ci.cachix.org"
            ];
            trusted-public-keys = [
              "nixcache.org-1:fd7sIL2BDxZa68s/IqZ8kvDsxsjt3SV4mQKdROuPoak="
              "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "fenix.cachix.org-1:ecJhr+RdYEdcVgUkjruiYhjbBloIEGov7bos90cZi0Q="
              "nix-darwin.cachix.org-1:n7gkud0jAyzI+nqLlfCq6tpMGpz3Q8L4wQsz14b2cDo="
              "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
              "deploy-rs.cachix.org-1:xfNobmiwF/vzvK1gpfediPwpdIP0rpDFikKp5dGG7NA="
              "crane.cachix.org-1:8Sw/sLmpKfTpXEd/ZEAxGHH2g6p5g+xOYnlz8+3nNQY="
              "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
              "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
            ];
          };
        };

        programs.zsh.enable = true;

        services.tailscale.enable = true;

        # Build user that the NixOS fleet's nix-daemon SSHes into. Authorize
        # each dispatching host's /root/.ssh/id_remote_builder.pub here.
        users.users.${username} = {
          name = username;
          home = "/Users/${username}";
          # PLACEHOLDER — add the NixOS hosts' remote-builder PUBLIC keys:
          # openssh.authorizedKeys.keys = self.lib.sshKeys.remoteBuilders;
        };

        system = {
          stateVersion = 4;
          primaryUser = username;
          startup.chime = false;
        };

        ids.gids.nixbld = 350;
      })

      self.darwinModules.darwin-nix-maintenance

      # DEFERRED — GitHub Actions runner + niks3 cache push. Wire these up in a
      # later pass (user opted "not yet"). Pattern is in ali-mba/default.nix:
      #   inputs.sops-nix.darwinModules.sops
      #   self.darwinModules.niks3-cache-push
      #   self.darwinModules.github-actions-runner
      #   + sops secrets (niks3-token, github-runner-token)
      #   + modules.niks3CachePush / modules.githubActionsRunner

      inputs.home-manager.darwinModules.home-manager
      {
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${username} = self.homeModules.home-macos;
        home-manager.extraSpecialArgs = commonArgs // {
          gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
          gitGPGSigningKey = "~/.ssh/id_personal.pub";
          gitUserName = "Alison Jenkins";
          github_clone_ssh_host_personal = "github.com";
          github_clone_ssh_host_work = "github.com";
          inherit hostname;
          primarySSHKey = "~/.ssh/id_personal.pub";
        };
      }
    ];
    specialArgs = commonArgs // {
      inherit hostname;
    };
  };
}
