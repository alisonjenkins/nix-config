{ specialArgs, inputs, ... }: {
  imports = [
    home-manager.nixosModules.home-manager
  ];

  home-manager.backupFileExtension = ".bak";
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${specialArgs.username} = import ../../home/home.nix;
  home-manager.extraSpecialArgs =
    specialArgs // {
      gitUserName = "Alison Jenkins";
      gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
      gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
    };
}
