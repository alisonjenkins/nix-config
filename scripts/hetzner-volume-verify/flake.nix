{
  description = "Dev shell for the Hetzner volume migration checks (specs/004-hetzner-encrypted-volumes)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            awscli2
            bats
            coreutils
            findutils
            gnugrep
            hcloud
            jq
            postgresql
            (python3.withPackages (ps: [ ps.lz4 ]))
            kubectl
            rsync
            shellcheck
          ] ++ lib.optional stdenv.hostPlatform.isLinux cryptsetup;
        };
      });
    };
}
