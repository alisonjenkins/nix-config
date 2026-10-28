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
      rea = (pkgsFor system).rea;
      sift = (pkgsFor system).sift;
      memory-recall = (pkgsFor system).memory-recall;
      token-tools = (pkgsFor system).token-tools;
      rootly-cli = (pkgsFor system).rootly-cli;
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

    # A flake update can move ghidra-bin or jdk21 out of the range REA
    # accepts (Ghidra 12.1.x, JDK 21+) and the failure only shows when an
    # agent opens a binary. Runs REA's own doctor, then a real decompile, on
    # exactly the Ghidra and JDK that programs.rea ships.
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      # The package builds with doCheck, so building it runs the workspace's
      # cargo tests; this makes `nix flake check` run them too.
      token-tools = (pkgsFor system).token-tools;

      rea-ghidra =
        let
          pkgs = pkgsFor system;
          ghidra = import (self + "/home/programs/rea/ghidra.nix") pkgs;
        in
        pkgs.runCommand "rea-ghidra"
          {
            nativeBuildInputs = [ pkgs.rea pkgs.jq pkgs.stdenv.cc pkgs.procps ];
            GHIDRA_INSTALL_DIR = ghidra.installDir;
            JAVA_HOME = ghidra.javaHome;
          } ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"

          rea doctor --provider ghidra --json > doctor.json || true
          jq -e '[.scope_checks[] | select(.name | startswith("ghidra"))]
                 | length > 0 and all(.ok)' doctor.json >/dev/null || {
            jq '.scope_checks[] | select(.name | startswith("ghidra")) | select(.ok | not)' doctor.json
            echo "rea doctor rejects the pinned Ghidra or JDK" >&2
            exit 1
          }

          cat > hello.c <<'EOF'
          #include <stdio.h>
          int main(void) { return puts("rea-ghidra-check"); }
          EOF
          cc -O1 -o hello hello.c

          rea decompile "$PWD/hello" main --provider ghidra --json > decompile.json || {
            cat decompile.json >&2
            echo "rea decompile failed with the pinned Ghidra and JDK" >&2
            exit 1
          }
          grep -q 'rea-ghidra-check' decompile.json || {
            cat decompile.json >&2
            echo "decompiled main does not contain the program's string" >&2
            exit 1
          }
          touch $out
        '';
    };
  };
}
