{ lib, ... }:
let
  primary = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
  phone = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2wZMFO69SYvoIIs6Atx/22PVy8wHtYy0MKpYtUMsez phone-ssh-key";
  # Dedicated key for nix-daemon (root) on ali-framework-laptop to
  # SSH into remote nix builders (ali-desktop, home-k8s-master-1).
  # Generated locally with:
  #     sudo ssh-keygen -t ed25519 -N "" -C "nix-builder-laptop" \
  #         -f /root/.ssh/id_remote_builder
  # Lives at /root/.ssh/id_remote_builder on ali-framework-laptop.
  # Authorize on hosts that should accept incoming nix builds via
  # nix.buildMachines.<entry>.sshKey = /root/.ssh/id_remote_builder.
  nixBuilderLaptop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDA14oK6m/gMcRaAUnMbiI1Tr5c3aLORWyzX2U+IU6Eq nix-builder-laptop";
  # Agent skills, shared across every agent runtime rather than owned by one.
  # Each entry is a directory holding SKILL.md plus its bundled child files
  # (languages/*.md, per-tool guides) — consumers must link the *directory*,
  # never SKILL.md alone, or the children silently disappear and the skill's
  # routing table points at nothing.
  #
  # These carry agentskills.io spec frontmatter only, so one directory serves
  # Claude Code, opencode, and anything else implementing the standard. The
  # conventions are documented in home/skills/skill-authoring/.
  skillsDir = ../home/skills;
  skillNames = lib.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir)
  );
in
{
  # skills.<name> -> path to that skill's directory. Auto-discovered: adding a
  # directory under home/skills/ is all it takes to expose it.
  flake.lib.skills = lib.genAttrs skillNames (name: skillsDir + "/${name}");

  flake.lib.sshKeys = {
    inherit primary phone nixBuilderLaptop;
    all = [
      primary
      phone
    ];
    # Convenience list for hosts acting as remote nix builders. Apply
    # to users.users.ali.openssh.authorizedKeys.keys so the laptop's
    # nix-daemon can dispatch jobs.
    remoteBuilders = [
      nixBuilderLaptop
    ];
  };
}
