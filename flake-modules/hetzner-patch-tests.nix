# Hermetic checks for the Hetzner in-place patch scripts: bats over
# scripts/hetzner-patch/tests/*.bats, shellcheck over scripts/hetzner-patch/*.sh.
# Globs, so new scripts and tests are picked up without editing this file.
#   nix build .#checks.x86_64-linux.hetzner-patch-scripts
{ self, ... }: {
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.hetzner-patch-scripts = pkgs.runCommand "hetzner-patch-scripts"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.bats
            pkgs.coreutils
            pkgs.findutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.shellcheck
          ];
        } ''
        set -euo pipefail
        dir=${self + "/scripts/hetzner-patch"}
        shopt -s nullglob
        tests=("$dir"/tests/*.bats)
        scripts=("$dir"/*.sh)
        if (( ''${#tests[@]} == 0 )); then
          echo "hetzner-patch-scripts: no *.bats under $dir/tests" >&2
          exit 1
        fi
        if (( ''${#scripts[@]} == 0 )); then
          echo "hetzner-patch-scripts: no *.sh under $dir" >&2
          exit 1
        fi
        bats "''${tests[@]}"
        shellcheck "''${scripts[@]}"
        touch $out
      '';
    };
}
