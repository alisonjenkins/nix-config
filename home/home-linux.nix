{ ... }: {
  imports = [
    ./home-common.nix
    ./programs
    ./programs/linux-only
  ];
}
