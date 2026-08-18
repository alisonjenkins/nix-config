{ specialArgs, inputs, pkgs, ... }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  # Must be a single executable: home-manager word-splits
  # $HOME_MANAGER_BACKUP_COMMAND and appends the target as $1.
  home-manager.backupCommand = "${pkgs.hm-backup-file}/bin/hm-backup-file";
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.${specialArgs.username} = import ../../home/home-linux.nix;
  home-manager.extraSpecialArgs =
    specialArgs // {
      gitUserName = "Alison Jenkins";
      gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
      gitGPGSigningKey = specialArgs.outputs.lib.sshKeys.primary;
    };
}
