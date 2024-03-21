{pkgs, ...}: {
  programs.gh = {
    enable = true;

    extensions = with pkgs; [
      gh-actions-cache
      gh-cal
      gh-dash
      gh-eco
      gh-markdown-preview
      gh-poi
    ];

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
