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
    packages = {
      positional-audio-bench = (pkgsFor system).positional-audio-bench;
      # Renovate bumps these packages' lockfiles, but cannot update the Nix
      # hash of their dependencies, so a bump can break the build while still
      # evaluating. Exposed here so the PR check builds them when they change.
      cavemem = (pkgsFor system).cavemem;
      sift = (pkgsFor system).sift;
      memory-recall = (pkgsFor system).memory-recall;
      token-tools = (pkgsFor system).token-tools;
      vr-foveation-bench = (pkgsFor system).vr-foveation-bench;
      containerd-prepopulate = (pkgsFor system).callPackage (self + "/pkgs/containerd-prepopulate") { };
    } //
      # camoufox-browser is a from-source patched-Firefox build (heavy); only
      # exposed/buildable on x86_64-linux, where CI compiles + caches it.
      lib.optionalAttrs (system == "x86_64-linux") {
        camoufox-browser = (pkgsFor system).camoufox-browser;

        # Pinned upstream llama.cpp (compiles from source); exposed so a bump
        # that breaks the override's patch/npm-deps assumptions shows up in CI.
        llama-cpp-upstream = (pkgsFor system).llama-cpp-upstream;
      };
  };
}
