{ pkgs, system, inputs, ... }:
let
  zoxide-config = pkgs.stdenv.mkDerivation {
    name = "nushell-zoxide-source";
    buildInputs = [ pkgs.zoxide ];
    dontUnpack = true;
    buildPhase = ''
      mkdir -p $out
      zoxide init nushell > $out/zoxide.nu
    '';
  };
in
{
  programs.nushell = {
    enable = true;

    extraConfig = ''
      source ${zoxide-config}/zoxide.nu
      source ~/.config/nushell/nnn-quitcd.nu
    '';
    shellAliases = {
      ll = "${pkgs.eza}/bin/eza -l --grid --git";
      ls = "${pkgs.eza}/bin/eza";
      lt = "${pkgs.eza}/bin/eza --tree --git --long";
      key = "${pkgs.openssh}/bin/ssh-add ~/.ssh/ssh_keys/id_bashton_alan";
      keyp = "${pkgs.openssh}/bin/ssh-add ~/.ssh/ssh_keys/id_personal";
      keypa = "${pkgs.openssh}/bin/ssh-add ~/.ssh/ssh_keys/id_alan-aws";
      keyk = "${pkgs.openssh}/bin/ssh-add ~/.ssh/ssh_keys/id_krystal";
      vim = "${inputs.ali-neovim.packages.${system}.nvim}/bin/nvim";
      vi = "${inputs.ali-neovim.packages.${system}.nvim}/bin/nvim";
      v = "${inputs.ali-neovim.packages.${system}.nvim}/bin/nvim";
      j = "${pkgs.just}/bin/just";
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../../";
      "......" = "cd ../../../../";
      "--" = "cd -";
      "cdd" = "cd ~/Downloads";
      "cdg" = "cd ~/git";
    };

    environmentVariables = { };
  };

  home.file = {
    ".config/nushell/nnn-quitcd.nu".text = builtins.readFile ./nnn-quitcd.nu;
  };
}
