{ inputs, self, ... }: {
  flake = {
    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;

    deploy = {
      nodes = {
        ali-framework-laptop = {
          hostname = "ali-framework-laptop-wifi.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-framework-laptop;
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

        home-k8s-server-1 = {
          hostname = "home-k8s-server-1.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-k8s-server-1;
            };
          };
        };
      };
    };
  };
}
