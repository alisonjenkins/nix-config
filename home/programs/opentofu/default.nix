{
  home.file = if builtins.getEnv "HOSTNAME" == "ali-work-laptop" then
  {}
  else
  {
    ".config/opentofu/tofurc".text = import ./tofurc.nix;
  };
}
