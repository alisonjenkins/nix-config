{ self, ... }: {
  # bats suite and alias lint for the time-management skill's tm script.
  # Model-free and network-free. Run with:
  #   nix build .#checks.<system>.skills-time-management
  perSystem = { pkgs, ... }:
    {
      checks.skills-time-management = pkgs.runCommand "skills-time-management"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.gawk pkgs.coreutils ];
        } ''
        bash ${self + "/home/skills/time-management/scripts/lint-aliases.sh"} \
          ${self + "/home/skills/time-management/scripts/backends"}
        bats ${self + "/home/skills/time-management/scripts"}/tests
        touch $out
      '';
    };
}
