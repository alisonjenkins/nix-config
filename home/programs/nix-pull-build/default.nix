{ config, lib, pkgs, ... }:
let
  cfg = config.programs.nix-pull-build;
  command = pkgs.writeShellApplication {
    name = "nix-pull-build";
    runtimeInputs = [ pkgs.git pkgs.nix pkgs.coreutils pkgs.jq ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.inetutils pkgs.libnotify ];
    text = ''
      repository=${lib.escapeShellArg cfg.repository}
    '' + builtins.readFile ./build.sh;
  };
in
{
  options.programs.nix-pull-build = {
    enable = lib.mkEnableOption "pull, build and notify for this system's nix-config"
      // { default = true; };
    repository = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/git/personal/nix-config";
      description = "Absolute path to the main nix-config checkout to update and build.";
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
        assertion = lib.hasPrefix "/" cfg.repository;
        message = "programs.nix-pull-build.repository must be an absolute path.";
      }
    ];
    home.packages = [ cfg.package ];
    programs.copilot-cli.trustedProjects.${cfg.repository}.commandPatterns = [
      "nix-pull-build"
    ];
    programs.claude-code.settings.permissions.allow = [
      "Bash(nix-pull-build)"
    ];
  };
}
