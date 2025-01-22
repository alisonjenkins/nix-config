{ specialArgs, inputs, ... }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager.backupFileExtension = ".bak";
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.ali = import ../../home/home.nix;
  home-manager.extraSpecialArgs =
    specialArgs
    // {
      username = "kal";
      gitUserName = "Kal Zaffar";
      gitEmail = "";
      gitGPGSigningKey = "";
    };
}
