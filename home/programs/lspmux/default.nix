{ pkgs, inputs, lib, ... }:
let
  lspmux = inputs.ali-neovim.packages.${pkgs.system}.lspmux;

  # Wrapper that exits 0 if the daemon is already running (port bound by Neovim)
  lspmuxStart = pkgs.writeShellScript "lspmux-start" ''
    ${lspmux}/bin/lspmux server 2>&1
    rc=$?
    # Exit 0 if the port is already bound (Neovim started the daemon first)
    if [ $rc -ne 0 ] && ${pkgs.iproute2}/bin/ss -tlnH sport = :27631 | grep -q LISTEN; then
      exit 0
    fi
    exit $rc
  '';
in
{
  # Linux: systemd user service
  systemd.user.services.lspmux = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "LSP Multiplexer Daemon";

    Service = {
      ExecStart = "${lspmuxStart}";
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
