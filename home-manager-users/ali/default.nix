{ specialArgs, inputs, pkgs, ... }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  # Use timestamp-based backups to prevent conflicts with existing backup files
  home-manager.backupCommand = ''
    ${pkgs.coreutils}/bin/mv -v "$1" "$1.backup-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
  '';
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${specialArgs.username} = import ../../home/home-linux.nix;
  home-manager.extraSpecialArgs =
    specialArgs // {
      gitUserName = "Alison Jenkins";
      gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
      gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
    };
}
