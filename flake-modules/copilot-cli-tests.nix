{ self, ... }: {
  # Hermetic bats tests for the copilot-cli activation scripts.
  # Run with: nix build .#checks.<system>.copilot-cli-bats
  perSystem = { pkgs, ... }:
    let
      scripts = import (self + "/home/programs/copilot-cli/scripts.nix") { inherit pkgs; };
    in
    {
      checks.copilot-cli-bats = pkgs.runCommand "copilot-cli-bats"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq ];
          JSON_MERGE = scripts.jsonMerge;
          TRUST_PROJECT = scripts.trustProject;
          TRUST_PARENTS = scripts.trustParents;
        } ''
        bats ${self + "/home/programs/copilot-cli/tests/scripts.bats"}
        touch $out
      '';
    };
}
