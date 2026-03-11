{
  description = "A Go project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;

        my-app = pkgs.buildGoModule {
          pname = "my-app";
          version = "0.1.0";
          src = ./.;
          vendorHash = null;
        };

        my-app-container = pkgs.dockerTools.buildLayeredImage {
          name = "my-app";
          tag = "latest";
          contents = [
            my-app
            pkgs.cacert
          ];
          config = {
            Cmd = [ "${my-app}/bin/my-app" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        my-app-container-stream = pkgs.dockerTools.streamLayeredImage {
          name = "my-app";
          tag = "latest";
          contents = [
            my-app
            pkgs.cacert
          ];
          config = {
            Cmd = [ "${my-app}/bin/my-app" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      in
      {
        checks = {
          inherit my-app;

          my-app-fmt = pkgs.runCommand "my-app-fmt" { nativeBuildInputs = [ pkgs.gofumpt ]; } ''
            cd ${./.}
            if [ -n "$(gofumpt -l .)" ]; then
              echo "Files not formatted with gofumpt:"
              gofumpt -l .
              exit 1
            fi
            touch $out
          '';
        };

        packages =
          {
            default = my-app;
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            container = my-app-container;
            container-stream = my-app-container-stream;
          };

        apps.default = flake-utils.lib.mkApp {
          drv = my-app;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            gopls
            golangci-lint
            gofumpt
            delve
            just
          ];
        };
      }
    );
}
