{ ... }: {
  flake.darwinModules = {
    darwin-nix-maintenance = import ../modules/darwin-nix-maintenance;
    llama-swap = import ../modules/llama-swap/darwin.nix;
    niks3-cache-push = import ../modules/niks3-cache-push/darwin.nix;
    github-actions-runner = import ../modules/github-actions-runner/darwin.nix;
  };
}
