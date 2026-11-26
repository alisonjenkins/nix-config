{ self, ... }: {
  # Hermetic unit tests for the `repo-audit` skill's scripts (branch-protection,
  # ci-pipeline, dependency-updates, dev-shell, forge, pre-commit, release-management,
  # report, secret-scanning). Run with: nix build .#checks.<system>.skills-repo-audit
  perSystem = { pkgs, ... }:
    {
      checks.skills-repo-audit = pkgs.runCommand "skills-repo-audit"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.git
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            pkgs.ripgrep
          ];
        } ''
        export HOME="$TMPDIR"
        export GIT_AUTHOR_NAME="test"
        export GIT_AUTHOR_EMAIL="test@example.com"
        export GIT_COMMITTER_NAME="test"
        export GIT_COMMITTER_EMAIL="test@example.com"
        git config --global commit.gpgsign false
        git config --global tag.gpgsign false
        cp -rL --no-preserve=mode ${self + "/home/skills/repo-audit/scripts"} "$TMPDIR/scripts"
        # The tests use a nix-shell shebang for running by hand; the check
        # already provides their tools, so run them with bash, and point
        # every shebang at the store since the sandbox has no /usr/bin/env.
        sed -i '1s|^#!/usr/bin/env nix-shell$|#!/usr/bin/env bash|' "$TMPDIR/scripts/tests"/*.test.sh
        sed -i '/^#! *nix-shell /d' "$TMPDIR/scripts/tests"/*.test.sh
        chmod +x "$TMPDIR/scripts/tests"/*.sh "$TMPDIR/scripts/checks"/*.sh "$TMPDIR/scripts"/*.sh
        patchShebangs "$TMPDIR/scripts"
        bash "$TMPDIR/scripts/tests/run-all.sh"
        touch "$out"
      '';
    };
}
