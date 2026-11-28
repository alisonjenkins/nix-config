{ pkgs, ... }: {
  home.file =
    if pkgs.stdenv.hostPlatform.isLinux then {
      ".config/yambar/config.yaml".text = builtins.readFile ./config.yaml;
    } else { };
}
