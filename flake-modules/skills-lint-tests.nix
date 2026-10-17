{ self, ... }: {
  # Convention lint for every shared skill under home/skills, plus the bats
  # suite for the linter itself. Model-free, so it costs no tokens.
  # Run with: nix build .#checks.<system>.skills-lint
  perSystem = { pkgs, ... }:
    {
      checks.skills-lint = pkgs.runCommand "skills-lint"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.yq-go ];
        } ''
        bash ${self + "/home/skills/skill-authoring/scripts/lint-skills.sh"} ${self + "/home/skills"}
        bats ${self + "/home/skills/skill-authoring/scripts"}/tests/lint-skills.bats
        touch $out
      '';
    };
}
