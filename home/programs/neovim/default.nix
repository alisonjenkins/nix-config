{
  inputs,
  system,
  ...
}: {
  home.packages = [
    inputs.ali-neovim.packages.${system}.nvim
  ];
}
