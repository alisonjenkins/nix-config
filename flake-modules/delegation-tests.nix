{ self, ... }: {
  # Hermetic bats tests for the `delegation` skill's scripts (delegate.sh,
  # delegate-to-local*.sh, switch/stop-local-profile.sh, queue-worker.sh).
  # Run with: nix build .#checks.<system>.delegation-bats
  perSystem = { pkgs, ... }:
    {
      checks.delegation-bats = pkgs.runCommand "delegation-bats"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq pkgs.python3 pkgs.curl pkgs.yq-go pkgs.git ];
        } ''
        bats ${self + "/home/skills/delegation/scripts"}/tests
        touch $out
      '';
    };
}
