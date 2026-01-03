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
    ]
    ++ lib.optional (hostname != null && builtins.pathExists (./machines + "/${hostname}")) ./machines/${hostname};
}
