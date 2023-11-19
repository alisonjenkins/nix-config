{ config, lib, pkgs, ... }:
{
  programs.gh = {
    enable = true;

    settings = {
      git_protocol = "ssh";
      prompt = "enabled";

      aliases = {
        co = "pr checkout";
        pv = "pr view";
        pvw = "pr view --web";
        rv = "repo view";
        rvw = "repo view --web";
      };
    };
  };
}
