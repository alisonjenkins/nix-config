{ inputs, system, pkgs, ... }:
{
  imports = [
    ./ssh
  ];

  environment.systemPackages = with pkgs; [
    git
    htop
    inputs.ali-neovim.packages.${system}.nvim
    just
    lshw
    nnn
    pciutils
    tmux
  ];
}
