{
  description = "An AWS Lambda Python project";

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

        my-lambda = python.pkgs.buildPythonApplication {
          pname = "my-lambda";
          version = "0.1.0";
          pyproject = true;
          src = ./.;

          build-system = [ python.pkgs.setuptools ];

          dependencies = [ python.pkgs.awslambdaric ];

          nativeCheckInputs = [ python.pkgs.pytest ];
          checkPhase = ''
            runHook preCheck
            pytest
            runHook postCheck
          '';
        };

        pythonEnv = python.withPackages (ps: [
          my-lambda
          ps.awslambdaric
        ]);

        my-lambda-container = pkgs.dockerTools.buildLayeredImage {
          name = "my-lambda";
          tag = "latest";
          contents = [
            pythonEnv
            pkgs.cacert
          ];
          config = {
            Cmd = [
              "${pythonEnv}/bin/python"
              "-m"
              "awslambdaric"
              "my_lambda.handler.handler"
            ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };

        my-lambda-container-stream = pkgs.dockerTools.streamLayeredImage {
          name = "my-lambda";
          tag = "latest";
          contents = [
            pythonEnv
            pkgs.cacert
          ];
          config = {
            Cmd = [
              "${pythonEnv}/bin/python"
              "-m"
              "awslambdaric"
              "my_lambda.handler.handler"
            ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      in
      {
        checks = {
          inherit my-lambda;

          my-lambda-ruff-check = pkgs.runCommand "my-lambda-ruff-check" { nativeBuildInputs = [ pkgs.ruff ]; } ''
            export RUFF_CACHE_DIR=$(mktemp -d)
            ruff check ${./.}
            touch $out
          '';

          my-lambda-ruff-format = pkgs.runCommand "my-lambda-ruff-format" { nativeBuildInputs = [ pkgs.ruff ]; } ''
            export RUFF_CACHE_DIR=$(mktemp -d)
            ruff format --check ${./.}
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
          buildInputs = [
            python
            pkgs.awscli2
            pkgs.ruff
            python.pkgs.pytest
            pkgs.just
          ];
        };
      }
    );
}
