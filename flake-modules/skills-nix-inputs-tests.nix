{ self, ... }: {
  # bats suite for the nix-inputs skill's detect-inputs.sh.
  # Model-free and network-free. Run with:
  #   nix build .#checks.<system>.skills-nix-inputs
  perSystem = { pkgs, ... }:
    {
      checks.skills-nix-inputs = pkgs.runCommand "skills-nix-inputs"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq pkgs.gnugrep pkgs.coreutils ];
        } ''
        bats ${self + "/home/skills/nix-inputs/scripts"}/tests
        touch $out
      '';
    };
}
