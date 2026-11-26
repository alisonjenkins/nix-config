{ self, ... }: {
  # Hermetic unit tests for the `docs-audit` skill's check.sh script.
  # Run with: nix build .#checks.<system>.skills-docs-audit
  perSystem = { pkgs, ... }:
    {
      checks.skills-docs-audit = pkgs.runCommand "skills-docs-audit"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gawk
            pkgs.git
            pkgs.gnugrep
            pkgs.gnused
            pkgs.ripgrep
          ];
        } ''
        export HOME="$TMPDIR"
        export GIT_AUTHOR_NAME="test"
        export GIT_AUTHOR_EMAIL="test@example.com"
        export GIT_COMMITTER_NAME="test"
        export GIT_COMMITTER_EMAIL="test@example.com"
        bash ${self + "/home/skills/docs-audit/scripts"}/tests/check.test.sh
        touch "$out"
      '';
    };
}
