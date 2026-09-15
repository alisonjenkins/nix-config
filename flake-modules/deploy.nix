{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  allDeployChecks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
in {
  flake = {
    # deploy-rs's own deployChecks bundles "deploy-schema" (cheap: validates
    # the deploy.nodes structure, no host evaluation) with "deploy-activate"
    # (expensive: realizes EVERY node's activation profile, which pulls in
    # that host's full system closure -- for this repo's ~10 nodes, that's
    # effectively building the whole fleet). `nix flake check` builds
    # everything under `checks` unconditionally, so leaving deploy-activate
    # wired in here means a routine flake check silently does a full-fleet
    # build every time -- confirmed live: building it alone ran this machine
    # out of RAM. Keep only deploy-schema in the default check sweep;
    # deploy-activate (and everything else deployChecks produces) stays
    # available on demand via the full un-filtered deployChecks below.
    checks = builtins.mapAttrs
      (system: checks: lib.filterAttrs (name: _: name != "deploy-activate") checks)
      allDeployChecks;

    # Un-filtered deployChecks, including the expensive deploy-activate:
    # `nix build .#deployChecks.<system>.deploy-activate` to run it by hand.
    deployChecks = allDeployChecks;

    deploy = {
      nodes = {
        ali-desktop = {
          hostname = "100.127.142.30";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-desktop;
            };
          };
        };

        ali-framework-laptop = {
          hostname = "ali-framework-laptop-wifi.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-framework-laptop;
            };
          };
        };

        ali-steam-deck = {
          hostname = "192.168.1.67";
          # The deck has no passwordless sudo for the login user, so connect as
          # root directly instead of escalating after login.
          sshUser = "root";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-steam-deck;
            };
          };
        };

        ali-mba-linux = {
          hostname = "ali-mba-linux";  # Tailscale MagicDNS
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.ali-mba-linux;
            };
          };
        };

        ali-work-laptop = {
          hostname = "ali-work-laptop.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-work-laptop;
            };
          };
        };

        download-server-1 = {
          hostname = "download-server-1.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.download-server-1;
            };
          };
        };

        home-kvm-hypervisor-1 = {
          hostname = "home-kvm-hypervisor-1.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-kvm-hypervisor-1;
            };
          };
        };

        home-storage-server-1 = {
          hostname = "home-storage-server-1.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-storage-server-1;
            };
          };
        };

        home-k8s-master-1 = {
          hostname = "home-k8s-master-1.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-k8s-master-1;
            };
          };
        };

        # home-k8s-server-1 = {
        #   hostname = "home-k8s-server-1.lan";
        #   profiles = {
        #     system = {
        #       user = "root";
        #       path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-k8s-server-1;
        #     };
        #   };
        # };
      };
    };
  };
}
