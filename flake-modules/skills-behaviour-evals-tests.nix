{ self, ... }: {
  # Offline gate for skill behaviour evals: every case under
  # home/skill-evals must be a valid `claude plugin eval` case for a skill
  # that exists. The live run is opt-in (spends model credit); see
  # docs/adr/0065-skill-behaviour-evals-with-claude-plugin-eval.md.
  # Run with: nix build .#checks.<system>.skills-behaviour-evals
  perSystem = { pkgs, ... }:
    {
      checks.skills-behaviour-evals = pkgs.runCommand "skills-behaviour-evals"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq pkgs.yq-go ];
        } ''
        bash ${self + "/home/skills/skill-authoring/scripts/run-behaviour-evals.sh"} --check \
          --skills ${self + "/home/skills"} --evals ${self + "/home/skill-evals"}
        bats ${self + "/home/skills/skill-authoring/scripts"}/tests/run-behaviour-evals.bats
        touch $out
      '';
    };
}
