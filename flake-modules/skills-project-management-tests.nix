{ self, ... }: {
  # bats suite and alias lint for the project-management skill's pm script.
  # Model-free and network-free (gh is faked). Run with:
  #   nix build .#checks.<system>.skills-project-management
  perSystem = { pkgs, ... }:
    {
      checks.skills-project-management = pkgs.runCommand "skills-project-management"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq pkgs.gawk pkgs.coreutils pkgs.git ];
        } ''
        bash ${self + "/home/skills/project-management/scripts/lint-aliases.sh"} \
          ${self + "/home/skills/project-management/scripts/backends"}
        bats ${self + "/home/skills/project-management/scripts"}/tests
        touch $out
      '';
    };
}
