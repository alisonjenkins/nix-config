{ self, ... }: {
  # Hermetic bats unit tests for the OBS config patch functions.
  # Run with: nix build .#checks.<system>.obs-config-bats
  perSystem = { pkgs, ... }: {
    checks.obs-config-bats = pkgs.runCommand "obs-config-bats" {
      nativeBuildInputs = [ pkgs.bats pkgs.bash pkgs.crudini pkgs.jq ];
    } ''
      cp -r ${self + "/home/programs/obs"}/. ./src
      chmod -R u+w ./src
      cd ./src
      bats tests/patch-config.bats
      touch $out
    '';
  };
}
