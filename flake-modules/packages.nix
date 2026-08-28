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

        # Canary for alisonjenkins/nix-config#226: home-k8s-master-1 pins
        # boot.kernelPackages to linux_7_1 because the legacy nvidia driver
        # (the only track supporting its passed-through GTX 1070/Pascal)
        # fails to build against linuxPackages_latest since Linux 7.2 removed
        # strncpy(). This builds the EXACT broken combination on a schedule
        # (.github/workflows/nvidia-kernel-canary.yaml) — the moment it
        # starts succeeding is the signal that nvidia/nixpkgs shipped a fix
        # and home-k8s-master-1's pin can be reverted.
        nvidia-kernel-canary = (pkgsFor system).linuxPackages_latest.nvidiaPackages.legacy_580;
      };
  };
}
