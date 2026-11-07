# packages.<linux>.cloud-kit: skills, mandates, agents and tools for Claude
# cloud sessions. See pkgs/cloud-kit/default.nix for how sessions get it, and
# docs/cloud-kit.md for the setup.
{ inputs, self, ... }:
let
  inherit (inputs.nixpkgs) lib;
  linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
  mandates = import (self + "/home/programs/shared-mandates.nix");
  agentsDir = self + "/home/programs/claude-code/agents";

  # Same overlay-applied nixpkgs the hosts use, so the tools match the laptops
  # and custom packages (sift) are available. CI pushes the closure to
  # cache.nixcache.org, so overlay-built paths still substitute in the cloud.
  pkgsFor = system: import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = lib.attrValues self.overlays;
  };

  # Tools the skills' scripts call that a cloud image lacks or ships in the
  # wrong flavour. git, curl and python3 come from the image, which configures
  # them for its proxy; the bootstrap links only what the image is missing.
  toolsFor = p: [
    p.bats
    p.fd
    p.file
    p.gh
    p.glab
    p.jq
    p.ripgrep
    p.shellcheck
    p.sift
    # Only the two util-linux binaries the skills call; the whole package
    # would link fdisk, mount, hwclock and ~90 more into /usr/local/bin.
    (p.runCommand "util-linux-column-flock" { } ''
      mkdir -p $out/bin
      ln -s ${p.util-linux}/bin/column ${p.util-linux}/bin/flock $out/bin/
    '')
    p.yq-go
  ];
in
{
  perSystem = { system, ... }: {
    packages = lib.optionalAttrs (lib.elem system linuxSystems) (
      let p = pkgsFor system; in {
        cloud-kit = p.callPackage (self + "/pkgs/cloud-kit") {
          anthropicSkills = p.callPackage (self + "/home/programs/claude-code/anthropic-skills.nix") { };
          skills = self.lib.skills;
          context = lib.concatStringsSep "\n" [
            mandates.gitStrategy
            (mandates.mkModelRouting "cloud")
            mandates.workStyle
          ];
          agents = {
            aws-iam-debugger = builtins.readFile (agentsDir + "/aws-iam-debugger.md");
            haiku-worker = builtins.readFile (agentsDir + "/haiku-worker.md");
            git-commit-generator = builtins.readFile (agentsDir + "/git-commit-generator.md") + "\n" + mandates.gitStrategy;
            pr-creator = builtins.readFile (agentsDir + "/pr-creator.md") + "\n" + mandates.gitStrategy;
          };
          tools = toolsFor p;
        };
      }
    );
  };
}
