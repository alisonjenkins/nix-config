{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    naersk.url = "github:nix-community/naersk";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = inputs @ {flake-parts, ...}:
  inputs.flake-parts.lib.mkFlake { inherit inputs; }
  {
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    imports = [
      ./nix/devshell.nix
      ./nix/package.nix
    ];
  };
}
