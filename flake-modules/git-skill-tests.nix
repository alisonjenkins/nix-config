{ self, ... }: {
  # Hermetic bats tests for the `git` skill's scripts (merge-onto-default.sh,
  # poll-pr-review.sh, pr-status.sh, rebase-onto-default.sh, watch-pr.sh, etc).
  # Run with: nix build .#checks.<system>.git-skill-bats
  perSystem = { pkgs, ... }:
    {
      checks.git-skill-bats = pkgs.runCommand "git-skill-bats"
        {
          nativeBuildInputs = [
            pkgs.bats
            pkgs.git
            pkgs.jq
            pkgs.openssh
            pkgs.coreutils
            pkgs.gnused
            pkgs.gawk
            pkgs.findutils
          ];
        } ''
        bats ${self + "/home/skills/git/scripts"}/tests
        touch $out
      '';
    };
}
