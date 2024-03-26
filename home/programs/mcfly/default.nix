{...}: {
  programs.mcfly = {
    enable = true;
    fuzzySearchFactor = 3;
    keyScheme = "vim";
    enableBashIntegration = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };
}
