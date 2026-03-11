{
  description = "An AWS Lambda Go project";

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

        my-lambda = pkgs.buildGoModule {
          pname = "my-lambda";
          version = "0.1.0";
          src = ./.;
          vendorHash = "sha256-KVtqVexZ2jvxaR4liQo22yXGdKUcmQMOzOlVG8Fjn88=";
          env.CGO_ENABLED = "0";
          ldflags = [
            "-s"
            "-w"
          ];
          postInstall = ''
            mv $out/bin/my-lambda $out/bin/bootstrap
          '';
        };

        my-lambda-container = pkgs.dockerTools.buildLayeredImage {
          name = "my-lambda";
          tag = "latest";
          contents = [
            my-lambda
            pkgs.cacert
          ];
          config = {
            Cmd = [ "${my-lambda}/bin/bootstrap" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        my-lambda-container-stream = pkgs.dockerTools.streamLayeredImage {
          name = "my-lambda";
          tag = "latest";
          contents = [
            my-lambda
            pkgs.cacert
          ];
          config = {
            Cmd = [ "${my-lambda}/bin/bootstrap" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      in
      {
        checks = {
          inherit my-lambda;

          my-lambda-fmt = pkgs.runCommand "my-lambda-fmt" { nativeBuildInputs = [ pkgs.gofumpt ]; } ''
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
            default = my-lambda;
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            container = my-lambda-container;
            container-stream = my-lambda-container-stream;
          };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            awscli2
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
