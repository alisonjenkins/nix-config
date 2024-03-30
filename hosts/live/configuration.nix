{
  inputs,
  system,
  ...
}:
{
  nix = {
    extraOptions = "experimental-features = nix-command flakes";
  };

  environment.systemPackages = [
    # inputs.ali-neovim.packages.${system}.nvim
  ];
}
