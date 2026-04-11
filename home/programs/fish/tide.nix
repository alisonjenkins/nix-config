# Tide prompt configuration for Fish (Powerlevel10k-like)
{
  pkgs,
  lib,
  # hostname is passed via extraSpecialArgs on hosts that set it; defaults to ""
  hostname ? "",
  ...
}: {
  programs.fish.plugins = [
    {
      name = "tide";
      src = pkgs.fetchFromGitHub {
        owner = "IlanCosman";
        repo = "tide";
        rev = "c4e3831dc4392979478d3d7b66a68f0274996c85";
        sha256 = "sha256-1ApDjBUZ1o5UyfQijv9a3uQJ/ZuQFfpNmHiDWzoHyuw=";
      };
    }
  ];

  # Alisons-MacBook-Pro uses a slimmer config (9 fewer right-prompt items) to
  # reduce per-render file-system checks under corporate AV scanning.
  home.file.".config/fish/conf.d/tide_config.fish".source =
    if hostname == "Alisons-MacBook-Pro"
    then ./tide_config_macbook.fish
    else ./tide_config.fish;
}
