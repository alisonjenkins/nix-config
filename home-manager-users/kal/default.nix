{ specialArgs, inputs }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager.backupFileExtension = ".bak";
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${specialArgs.username} = import ../../home/home.nix;
  home-manager.extraSpecialArgs =
    specialArgs
    // {
      gitUserName = "Kal Zaffar";
      gitEmail = "";
      gitGPGSigningKey = "";
    };
}
