# Hermetic checks for the kernel livepatch tooling: bats over
# scripts/livepatch/tests/*.bats, shellcheck over scripts/livepatch/*.sh.
# Globs, so new scripts and tests are picked up without editing this file.
#   nix build .#checks.x86_64-linux.livepatch-scripts
{ self, ... }: {
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.livepatch-scripts = pkgs.runCommand "livepatch-scripts"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.bats
            pkgs.coreutils
            pkgs.findutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.gnused
            pkgs.shellcheck
          ];
        } ''
        set -euo pipefail
        dir=${self + "/scripts/livepatch"}
        shopt -s nullglob
        tests=("$dir"/tests/*.bats)
        scripts=("$dir"/*.sh)
        if (( ''${#tests[@]} == 0 )); then
          echo "livepatch-scripts: no *.bats under $dir/tests" >&2
          exit 1
        fi
        if (( ''${#scripts[@]} == 0 )); then
          echo "livepatch-scripts: no *.sh under $dir" >&2
          exit 1
        fi
        for s in "''${scripts[@]}"; do
          if [[ "$(head -c 2 "$s")" == '#!' && ! -x "$s" ]]; then
            echo "livepatch-scripts: $s has a shebang but is not executable" >&2
            exit 1
          fi
        done
        shellcheck -x -P SCRIPTDIR "''${scripts[@]}"
        # The sandbox has no /usr/bin/env; run the tests on a copy with patched shebangs.
        work=$(mktemp -d)/livepatch
        cp -r "$dir" "$work"
        chmod -R u+w "$work"
        patchShebangs "$work"
        bats "$work"/tests/*.bats
        touch $out
      '';
    };
}
