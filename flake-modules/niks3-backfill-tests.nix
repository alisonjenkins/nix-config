{ self, ... }: {
  # Hermetic bats unit tests for the niks3-backfill shell logic.
  # Run with: nix build .#checks.<system>.niks3-backfill-bats
  perSystem = { pkgs, ... }: {
    checks.niks3-backfill-bats = pkgs.runCommand "niks3-backfill-bats" {
      nativeBuildInputs = [ pkgs.bats pkgs.bash ];
    } ''
      cp -r ${self + "/modules/niks3-cache-push"}/. ./src
      chmod -R u+w ./src
      cd ./src
      bats tests/backfill.bats
      touch $out
    '';
  };
}
