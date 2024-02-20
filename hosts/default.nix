{ inputs
, self
, withSystem
, sharedModules
, desktopModules
, homeImports
, modulesPath
, ...
}: {
  flake.nixosConfigurations = withSystem "x86_64-linux" ({ system, ... }:
    let
      lib = inputs.nixpkgs_stable.lib;
      specialArgs =
        let gpgSigningKey = "B561E7F6";
        in
        {
          inherit gpgSigningKey;
          inherit inputs;
          inherit system;
        };
    in
    {
      ali-desktop = inputs.nixpkgs_stable.lib.nixosSystem {
        inherit system;

        modules =
          [
            ./ali-desktop/configuration.nix
            # ../app-profiles/desktop/aws
            # ../app-profiles/desktop/display-managers/greetd
            # ../app-profiles/desktop/wms/hypr
            # ../app-profiles/desktop/wms/plasma5
            # inputs.hyprland.nixosModules.default
            # inputs.nix-flatpak.nixosModules.nix-flatpak
            # inputs.nur.nixosModules.nur
            # (modulesPath + "/installer/scan/not-detected.nix")
            # (modulesPath + "/profiles/qemu-guest.nix")
            inputs.chaotic.nixosModules.default
            inputs.nix-gaming.nixosModules.pipewireLowLatency
            inputs.sops-nix.nixosModules.sops
            # inputs.home-manager.nixosModules.home-manager
            # {
            #   home-manager.useGlobalPkgs = true;
            #   home-manager.useUserPackages = true;
            #   home-manager.users.ali = import ../home/home.nix;
            #   home-manager.extraSpecialArgs = specialArgs;
            # }
          ];
        # ++ sharedModules
        # ++ desktopModules;
      };
    });
}
