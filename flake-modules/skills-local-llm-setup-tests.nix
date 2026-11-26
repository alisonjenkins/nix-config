{ self, ... }: {
  # Hermetic unit and runner tests for the `local-llm-setup` skill's scripts
  # and benchmark harness. Run with: nix build .#checks.<system>.skills-local-llm-setup
  perSystem = { pkgs, ... }:
    {
      checks.skills-local-llm-setup = pkgs.runCommand "skills-local-llm-setup"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.python3
          ];
        } ''
        export HOME="$TMPDIR"
        export PYTHONDONTWRITEBYTECODE=1
        # Tests copy fixtures out of their own tree and then edit them, so
        # they need a writable copy, not the read-only store path.
        cp -rL ${self + "/home/skills/local-llm-setup/scripts"} "$TMPDIR/scripts"
        chmod -R u+w "$TMPDIR/scripts"
        patchShebangs "$TMPDIR/scripts"
        cd "$TMPDIR/scripts"
        python3 -m unittest discover -s tests -p 'test_*.py'
        bash tests/test-lib.sh
        python3 -m unittest discover -s bench/tests -p 'test_*.py'
        bash bench/tests/test-runner.sh
        touch "$out"
      '';
    };
}
