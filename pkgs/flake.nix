# This file turns your project into a Nix Flake.
# It defines all inputs and outputs explicitly.
{
  description = "A flake for building custom packages";

  # Define the inputs for this project. Here, we only need nixpkgs.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  # Define the outputs of this project (packages, apps, etc.).
  outputs = { self, nixpkgs }:
    let
      # We want our packages to be available on common systems.
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      # A helper to generate outputs for each supported system.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Create a `pkgs` instance for each system.
      pkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          # You could add overlays here if needed
        }
      );
    in
    {
      # The `legacyPackages` attribute makes your packages available to
      # older tools and commands like `nix-build`.
      legacyPackages = forAllSystems (system:
        # We call your package set function with the correct `pkgs` for the system.
        (import ./default.nix) pkgsFor.${system}
      );

      # The modern `packages` attribute is the standard for flakes.
      packages = forAllSystems (system:
        (import ./default.nix) pkgsFor.${system}
      );
    };
}
