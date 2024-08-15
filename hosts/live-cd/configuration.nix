{
  inputs,
  pkgs,
  ...
}: let
  getLatestNixConfigs = pkgs.writeShellScriptBin "get-latest-configs" ''
    ${pkgs.git}/bin/git clone https://github.com/alisonjenkins/nix-config $1
  '';

  mountSystemVolumes = pkgs.writeShellScriptBin "mount-system-volumes" ''
    SYSTEM=$1

    sudo dmraid -ay

    test -d /tmp/nix-configs || ${getLatestNixConfigs} /tmp/nix-configs
    cd /tmp/nix-configs/hosts/$SYSTEM/


  '';
in {
  environment = {
    systemPackages = with pkgs; [
      dmraid
      getLatestNixConfigs
      git
      inputs.ali-neovim.packages.${system}.nvim
      tmux
    ];
  };
}
