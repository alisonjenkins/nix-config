{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;

  # Central registry of AMI configurations
  amiConfigs = {
    aws-base-server = {
      system = "x86_64-linux";
      hostConfig = ../hosts/aws-base-server/configuration.nix;
      extraModules = [];
    };

    aws-base-server-arm = {
      system = "aarch64-linux";
      hostConfig = ../hosts/aws-base-server/configuration.nix;
      extraModules = [{
        ec2.efi = true;
        networking.hostName = lib.mkForce "aws-base-server-arm";
      }];
    };

    aws-k8s-node = {
      system = "x86_64-linux";
      hostConfig = ../hosts/aws-k8s-node/configuration.nix;
      extraModules = [];
    };

    aws-k8s-node-arm = {
      system = "aarch64-linux";
      hostConfig = ../hosts/aws-k8s-node/configuration.nix;
      extraModules = [{
        ec2.efi = true;
        networking.hostName = lib.mkForce "aws-k8s-node-arm";
      }];
    };
  };

  mkAmiSystem = _name: cfg:
    lib.nixosSystem {
      system = cfg.system;

      specialArgs = {
        username = "ali";
        inherit inputs outputs;
        system = cfg.system;
      };

      modules = [
        cfg.hostConfig
      ] ++ cfg.extraModules;
    };

  amiSystems = lib.mapAttrs mkAmiSystem amiConfigs;
in
{
  flake.nixosConfigurations = amiSystems;

  perSystem = { system, ... }: {
    packages = lib.mapAttrs'
      (name: _: lib.nameValuePair "${name}-ami" amiSystems.${name}.config.system.build.images.amazon)
      (lib.filterAttrs (_: cfg: cfg.system == system) amiConfigs);
  };
}
