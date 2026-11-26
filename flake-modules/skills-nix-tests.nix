{ self, ... }: {
  # bats suite for the nix skill's detect-inputs.sh.
  # Model-free and network-free. Run with:
  #   nix build .#checks.<system>.skills-nix
  perSystem = { pkgs, ... }:
    {
      checks.skills-nix = pkgs.runCommand "skills-nix"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq pkgs.gnugrep pkgs.coreutils ];
        } ''
        bats ${self + "/home/skills/nix/scripts"}/tests
        touch $out
      '';
    };
}
