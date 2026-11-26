{ self, ... }: {
  # Gate for skill-script mutation results: every script under
  # home/skills/*/scripts must be paired with tests or excluded, and the
  # recorded baseline must match the current script and test files. It runs
  # no mutants; see docs/adr/0066-incremental-mutation-testing-for-skill-scripts.md.
  # Run with: nix build .#checks.<system>.skills-mutation
  perSystem = { pkgs, ... }:
    {
      checks.skills-mutation = pkgs.runCommand "skills-mutation"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq pkgs.coreutils ];
        } ''
        bash ${self + "/home/skills/skill-authoring/scripts/mutate-scripts.sh"} --check \
          --root ${self + "/home/skills"}
        bats ${self + "/home/skills/skill-authoring/scripts"}/tests/mutate-scripts.bats
        touch $out
      '';
    };
}
