{ inputs, ... }: {
  perSystem = { system, ... }: {
    devShells.default =
      let
        sysPkgs = import inputs.nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };
        buildInputs = with sysPkgs; [
          deploy-rs
          just
          libsecret
          nix-fast-build
          nixos-anywhere
        ];
      in
      sysPkgs.mkShell {
        inherit buildInputs;
      };
  };
}
