{ pkgs, inputs, lib, ... }:
let
  lspmux = inputs.ali-neovim.packages.${pkgs.system}.lspmux;
in
{
  # Linux: systemd user service
  systemd.user.services.lspmux = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "LSP Multiplexer Daemon";

    Service = {
      ExecStart = "${lspmux}/bin/lspmux server";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = [ "default.target" ];
  };

  # macOS: launchd agent
  launchd.agents.lspmux = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${lspmux}/bin/lspmux" "server" ];
      KeepAlive = true;
      RunAtLoad = true;
      Label = "com.lspmux.daemon";
    };
  };
}
