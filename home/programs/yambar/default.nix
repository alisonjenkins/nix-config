{ pkgs, ... }: {
  home.file =
    if pkgs.stdenv.isLinux then {
      ".config/yambar/config.yaml".text = builtins.readFile ./config.yaml;
    } else { };
}
