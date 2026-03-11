{
  description = "A Python project";

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

        python = pkgs.python3;

        my-app = python.pkgs.buildPythonApplication {
          pname = "my-app";
          version = "0.1.0";
          pyproject = true;
          src = ./.;

          build-system = [ python.pkgs.setuptools ];

          nativeCheckInputs = [ python.pkgs.pytest ];
          checkPhase = ''
            runHook preCheck
            pytest
            runHook postCheck
          '';
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

          my-app-ruff-check = pkgs.runCommand "my-app-ruff-check" { nativeBuildInputs = [ pkgs.ruff ]; } ''
            export RUFF_CACHE_DIR=$(mktemp -d)
            ruff check ${./.}
            touch $out
          '';

          my-app-ruff-format = pkgs.runCommand "my-app-ruff-format" { nativeBuildInputs = [ pkgs.ruff ]; } ''
            export RUFF_CACHE_DIR=$(mktemp -d)
            ruff format --check ${./.}
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
          buildInputs = [
            python
            pkgs.ruff
            python.pkgs.pytest
            pkgs.just
          ];
        };
      }
    );
}
