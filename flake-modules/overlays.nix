{ inputs, self, ... }: {
  flake.overlays = import ../overlays { inherit inputs self; };
}
