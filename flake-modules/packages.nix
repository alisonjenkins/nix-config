# Expose selected custom packages from pkgs/ as flake `packages.<system>.*`
# so they can be built directly with `nix build .#<name>` and wired into CI.
# Custom packages otherwise only live inside the overlay (self.overlays) and
# aren't reachable as flake outputs.
{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;

  # Snap to a per-system overlay-applied nixpkgs set (same overlays the hosts
  # use) so the exposed package matches what would be deployed.
  pkgsFor = system: import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = lib.attrValues self.overlays;
  };
in
{
  perSystem = { system, ... }: {
    packages =
      # camoufox-browser is a from-source patched-Firefox build (heavy); only
      # exposed/buildable on x86_64-linux, where CI compiles + caches it.
      lib.optionalAttrs (system == "x86_64-linux") {
        camoufox-browser = (pkgsFor system).camoufox-browser;
      };
  };
}
