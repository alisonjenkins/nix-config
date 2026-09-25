# The local-model profiles the delegation skill's scripts load on demand
# (home/skills/delegation/delegate-to-local.md, "Profiles"), declared per
# host because what fits depends on the machine's GPU. A host that sets no
# profiles gets no file: ali-work-laptop runs one always-on llama-server
# through modules/llama-cpp instead.
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.delegateToLocal;

  profileModule = lib.types.submodule {
    options = {
      runtime = lib.mkOption {
        type = lib.types.enum [ "llama-server" "mlx-lm" "mock" ];
        default = "llama-server";
        description = "Server that loads the model.";
      };
      model = lib.mkOption {
        type = lib.types.str;
        description = "Model file (llama-server), or path or repo id (mlx-lm).";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port the server listens on.";
      };
      launchArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Extra server arguments. Include --ctx-size: delegate-to-local-agent.sh
          reads it to tell opencode the real context window.
        '';
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Shown by list-local-profiles.sh.";
      };
    };
  };

  toToml = _name: p: {
    inherit (p) runtime model port description;
    launch_args = p.launchArgs;
  };
in
{
  options.modules.delegateToLocal.profiles = lib.mkOption {
    type = lib.types.attrsOf profileModule;
    default = { };
    description = "Local model profiles, by name. Empty leaves profiles.toml unmanaged.";
  };

  config = lib.mkIf (cfg.profiles != { }) {
    xdg.configFile."delegate-to-local/profiles.toml".source =
      (pkgs.formats.toml { }).generate "delegate-to-local-profiles.toml"
        (lib.mapAttrs toToml cfg.profiles);
  };
}
