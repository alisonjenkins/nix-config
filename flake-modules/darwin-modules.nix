{ ... }: {
  flake.darwinModules = {
    niks3-cache-push = import ../modules/niks3-cache-push/darwin.nix;
    github-actions-runner = import ../modules/github-actions-runner/darwin.nix;
  };
}
