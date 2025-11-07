# Tide prompt configuration for Fish (Powerlevel10k-like)
{
  pkgs,
  lib,
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

  # Tide configuration (Rainbow style with custom settings)
  home.file.".config/fish/conf.d/tide_config.fish".source = ./tide_config.fish;
}
