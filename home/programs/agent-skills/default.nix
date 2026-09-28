{ lib, inputs, ... }:
{
  # Skills from home/skills/ (flake.lib.skills) in ~/.agents/skills, the
  # personal skills path read by both opencode and GitHub Copilot CLI.
  # Claude Code does not read it, so claude-code links its own copy into
  # ~/.claude/skills. Linked as whole directories so each family's children
  # (languages/*.md, per-tool guides) come along.
  home.file = lib.mapAttrs' (
    name: path: lib.nameValuePair ".agents/skills/${name}" { source = path; }
  ) inputs.self.lib.skills;
}
