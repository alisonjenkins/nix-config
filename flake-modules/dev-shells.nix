{ inputs, ... }: {
  perSystem = { system, pkgs, ... }: {
    devShells.default = pkgs.mkShellNoCC {
      packages = with inputs.nixpkgs.legacyPackages.${system}; [
        deploy-rs
        just
        libsecret
        nix-fast-build
        nixos-anywhere
        pv
        uplosi
      ];
    };
  };
}
