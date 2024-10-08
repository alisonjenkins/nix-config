{pkgs, ...}: {
  nix = {
    package = pkgs.nix;

    settings = {
      trusted-users = ["root" "@wheel"];
      experimental-features = "nix-command flakes";
    };
  };
}
