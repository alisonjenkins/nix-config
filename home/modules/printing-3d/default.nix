{ config, lib, pkgs, ... }:
let
  cfg = config.modules.printing3d;
in
{
  options.modules.printing3d = {
    enable = lib.mkEnableOption "the 3d-printing Claude Code skill (design, Qidi Studio slicing, Moonraker printing)";

    skills = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = pkgs.linkFarm "printing-3d-skills" [
        { name = "3d-printing"; path = ./skills/3d-printing; }
      ];
      description = "Directory of skill directories, merged into Claude Code's skills by programs/claude-code.";
    };
  };

  # The skill is host-specific (this machine's Qidi printer, qidi-studio and
  # openscad installs), so it is not in home/skills. Nothing to configure: the
  # option only gates whether programs/claude-code links the skill.
  config = lib.mkIf cfg.enable { };
}
