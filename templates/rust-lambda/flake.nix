{
  description = "An AWS Lambda function in Rust";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane.url = "github:ipetkov/crane";

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      flake-utils,
      rust-overlay,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        inherit (pkgs) lib;

        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        src = craneLib.cleanCargoSource ./.;

        commonArgs = {
          inherit src;
          strictDeps = true;

          buildInputs =
            [
              # Add additional build inputs here
              # pkgs.openssl
            ]
            ++ lib.optionals pkgs.stdenv.isDarwin [
              pkgs.libiconv
              pkgs.darwin.apple_sdk.frameworks.Security
              pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
            ];

          nativeBuildInputs = [
            # pkgs.pkg-config
          ];
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        my-lambda = craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;
            doCheck = false;
          }
        );

        my-lambda-container = pkgs.dockerTools.buildLayeredImage {
          name = "my-lambda";
          tag = "latest";
          contents = [
            my-lambda
            pkgs.cacert
          ];
          config = {
            Cmd = [ "${my-lambda}/bin/my-lambda" ];
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
          };
        };
      in
      {
        checks = {
          inherit my-lambda;

          my-lambda-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );

          my-lambda-doc = craneLib.cargoDoc (
            commonArgs
            // {
              inherit cargoArtifacts;
            }
          );

          my-lambda-fmt = craneLib.cargoFmt {
            inherit src;
          };

          my-lambda-nextest = craneLib.cargoNextest (
            commonArgs
            // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
              cargoNextestExtraArgs = "--no-tests=warn";
            }
          );
        };

        packages =
          {
            default = my-lambda;
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            container = my-lambda-container;
          };

        devShells.default = craneLib.devShell {
          checks = self.checks.${system};

          packages = with pkgs; [
            awscli2
            bacon
            cargo-edit
            cargo-expand
            cargo-lambda
            cargo-nextest
            cargo-watch
            just
          ];
        };
      }
    );
}
