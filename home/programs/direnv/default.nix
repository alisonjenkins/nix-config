{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;

    enableBashIntegration = true;
    enableFishIntegration = false; # handled by tool_init_cache.fish with caching
    enableNushellIntegration = true;
    enableZshIntegration = true;
  };
}
