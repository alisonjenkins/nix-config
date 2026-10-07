{
  description = "Retrieval eval harness: BM25 vs embedding models over Claude memories and skill chunks";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            cargo
            clippy
            rustc
            rustfmt
            rust-analyzer
            cargo-nextest
            pkg-config
            # bench/run.sh and bench/compare.sh
            curl
            jq
            sqlite
            util-linux
          ];
        };
      });
    };
}
