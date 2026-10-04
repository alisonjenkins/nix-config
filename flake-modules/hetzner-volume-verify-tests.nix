{ self, ... }: {
  # Hermetic bats tests for scripts/hetzner-volume-verify (verify.sh, retain-pv.sh,
  # destroy-old-volume.sh, check-no-call.sh, table-checksums.sql). kubectl, lsblk, cryptsetup,
  # curl and hcloud are fakes in tests/bin; sql.bats starts a throwaway Postgres.
  # Run with: nix build .#checks.<system>.hetzner-volume-verify-bats
  perSystem = { pkgs, ... }:
    {
      checks.hetzner-volume-verify-bats = pkgs.runCommand "hetzner-volume-verify-bats"
        {
          nativeBuildInputs = [
            pkgs.bats
            pkgs.coreutils
            pkgs.diffutils
            pkgs.findutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            pkgs.postgresql
            (pkgs.python3.withPackages (ps: [ ps.lz4 ]))
          ];
        } ''
        # The sandbox has no /usr/bin/env, so rewrite the scripts' shebangs on a writable copy.
        cp -r ${self + "/scripts/hetzner-volume-verify"} work
        chmod -R u+w work
        patchShebangs work
        bats work/tests
        touch $out
      '';
    };
}
