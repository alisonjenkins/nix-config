{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;

  # Common module for all AMIs — UEFI boot for NitroTPM, Secure Boot, and
  # forward-compatibility with newer instance families.
  commonAmiModule = { ec2.efi = true; };

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
        networking.hostName = lib.mkForce "aws-k8s-node-arm";
      }];
    };

    aws-nix-builder = {
      system = "x86_64-linux";
      hostConfig = ../hosts/aws-nix-builder/configuration.nix;
      extraModules = [];
    };

    aws-nix-builder-arm = {
      system = "aarch64-linux";
      hostConfig = ../hosts/aws-nix-builder/configuration.nix;
      extraModules = [{
        networking.hostName = lib.mkForce "aws-nix-builder-arm";
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
        commonAmiModule
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
