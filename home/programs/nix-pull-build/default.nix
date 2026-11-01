{ config, lib, pkgs, ... }:
let
  cfg = config.programs.nix-pull-build;
  command = pkgs.writeShellApplication {
    name = "nix-pull-build";
    runtimeInputs = [ pkgs.git pkgs.nix pkgs.coreutils pkgs.jq ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.inetutils pkgs.libnotify ];
    text = ''
      configured_repository=${lib.escapeShellArg (toString cfg.repository)}
      expected_origin=${lib.escapeShellArg cfg.origin}
    '' + builtins.readFile ./build.sh;
  };
in
{
  options.programs.nix-pull-build = {
    enable = lib.mkEnableOption "pull, build and notify for this system's nix-config"
      // { default = true; };
    origin = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/alisonjenkins/nix-config.git";
      description = ''
        Remote a checkout's origin must match, ignoring scheme and a .git
        suffix, for the command to pick it from the working directory.
      '';
    };
    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path to the main nix-config checkout, used when the command is
        not run from inside a checkout of `origin`. The command otherwise finds
        the checkout from the working directory. Setting it also pre-approves
        the command for that checkout in Copilot CLI.
      '';
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = command;
      description = "The repository-bound build command.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin || pkgs.stdenv.hostPlatform.isLinux;
        message = "programs.nix-pull-build supports macOS and Linux.";
      }
      {
        assertion = cfg.repository == null || lib.hasPrefix "/" cfg.repository;
        message = "programs.nix-pull-build.repository must be an absolute path.";
      }
    ];
    home.packages = [ cfg.package ];
    programs.copilot-cli.trustedProjects = lib.mkIf (cfg.repository != null) {
      ${cfg.repository}.commandPatterns = [ "nix-pull-build" ];
    };
    programs.claude-code.settings.permissions.allow = [
      "Bash(nix-pull-build)"
    ];
  };
}
