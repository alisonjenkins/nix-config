{pkgs, inputs, ...}: {
  home.packages = [
    inputs.stasis
  ];

  home.file = {
    ".config/stasis/stasis.rune".text = (import ./stasis.rune.nix);
    ".config/systemd/user/stasis.service".text = (import ./systemd.service.nix);
  };
}
