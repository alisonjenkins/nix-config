{
  inputs,
  lib,
  hostname ? null,
  ...
}: {
  imports =
    [
      ./home-common.nix
      ./programs
      ./programs/linux-only
      inputs.nixcord.homeModules.nixcord
      inputs.sops-nix.homeManagerModules.sops
      inputs.zen-browser.homeModules.default
    ]
    ++ lib.optional (hostname != null && builtins.pathExists (./machines + "/${hostname}")) ./machines/${hostname};

  # stylix module is Linux-only (loaded via nixosModules.desktop); Darwin has no stylix
  stylix.enableReleaseChecks = false;
}
