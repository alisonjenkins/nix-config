{ config, lib, pkgs, workIdentity, workIdentitySecretsFile, ... }:
let
  cfg = config.modules.rootly;
in
{
  options.modules.rootly = {
    enable = lib.mkEnableOption "the Rootly CLI and the /oncall-rota Claude Code skill";

    skills = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = pkgs.linkFarm "rootly-skills" [
        { name = "oncall-rota"; path = ./skills/oncall-rota; }
      ];
      description = "Directory of skill directories, merged into Claude Code's skills by programs/claude-code.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.rootly-cli ];

    # The /oncall-rota message and its Slack channel name the employer, so they
    # are decrypted from the work identity sops file instead of being committed
    # to this public repo.
    sops.secrets = lib.mkIf workIdentity (
      lib.genAttrs [ "template.md" "channel" ] (file: {
        sopsFile = workIdentitySecretsFile;
        mode = "0600";
        key = "oncall_rota_${lib.removeSuffix ".md" file}";
        path = "${config.xdg.configHome}/oncall-rota/${file}";
      })
    );
  };
}
