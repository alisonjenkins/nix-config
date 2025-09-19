{
  inputs,
  ...
}: {
  imports = [
    ./home-common.nix
    ./programs
    ./programs/linux-only
    inputs.nixcord.homeModules.nixcord
  ];
}
