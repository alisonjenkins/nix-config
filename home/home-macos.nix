{ inputs, ... }: {
  imports = [
    ./programs/macos-only
    ./programs
    ./home-common.nix
    inputs.sops-nix.homeManagerModules.sops
  ];
}
