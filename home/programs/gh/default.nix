{pkgs, ...}: {
  programs.gh = {
    enable = true;

    extensions = with pkgs; [
      unstable.gh-actions-cache
      unstable.gh-cal
      unstable.gh-dash
      unstable.gh-eco
      unstable.gh-markdown-preview
      unstable.gh-poi
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
