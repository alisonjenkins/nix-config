{ self, ... }: {
  # Hermetic bats tests for .github/scripts/pr-check-x86_64-linux.sh (parallel
  # sections, batched-eval fallback, cancellation). nix and git are fakes the
  # test writes itself.
  # Run with: nix build .#checks.<system>.pr-check-bats
  perSystem = { pkgs, ... }:
    {
      checks.pr-check-bats = pkgs.runCommand "pr-check-bats"
        {
          nativeBuildInputs = [
            pkgs.bats
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.jq
          ];
        } ''
        cp -r ${self + "/.github/scripts"} work
        chmod -R u+w work
        bats work/tests
        touch $out
      '';
    };
}
