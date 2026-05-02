{ ... }: {
  flake.darwinModules = {
    niks3-cache-push = import ../modules/niks3-cache-push/darwin.nix;
  };
}
