{ self, ... }: {
  # Vocabulary gate for skill descriptions: every phrase in a skill's
  # triggers.json must share a word with its description. Model-free.
  # Run with: nix build .#checks.<system>.skills-triggers
  perSystem = { pkgs, ... }:
    {
      checks.skills-triggers = pkgs.runCommand "skills-triggers"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq pkgs.yq-go ];
        } ''
        bash ${self + "/home/skills/skill-authoring/scripts/check-triggers.sh"} ${self + "/home/skills"}
        bats ${self + "/home/skills/skill-authoring/scripts"}/tests/check-triggers.bats
        bats ${self + "/home/skills/skill-authoring/scripts"}/tests/eval-triggers.bats
        touch $out
      '';
    };
}
