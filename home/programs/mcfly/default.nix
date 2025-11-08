{ pkgs, ... }:
let
  mcfly_init = pkgs.stdenv.mkDerivation {
    name = "mcfly-init";

    dontUnpack = true;
    buildInputs = [ pkgs.mcfly ];

    buildPhase = ''
      mcfly init zsh > $out
    '';
  };
  zshViModeEnabled = true;
in
{
  programs.mcfly = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = false; # Handled manually below for zsh-vi-mode compatibility
    keyScheme = "emacs";
  };

  programs.zsh.initContent =
    if zshViModeEnabled
    then ''
      function mcfly_init() {
        source ${mcfly_init}
      }
      zvm_after_init_commands+=(mcfly_init)
    ''
    else ''
      source ${mcfly_init}
    '';
}
