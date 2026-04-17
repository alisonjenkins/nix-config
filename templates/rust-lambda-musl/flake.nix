{
  description = "An AWS Lambda function in Rust with musl static linking";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane.url = "github:ipetkov/crane";

    flake-utils.url = "github:numtide/flake-utils";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      flake-utils,
      fenix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ fenix.overlays.default ];
        };

        inherit (pkgs) lib;

        # Musl target mapping for static Linux builds
        muslTargets = {
          "x86_64-linux" = {
            target = "x86_64-unknown-linux-musl";
            crossPkgs = pkgs.pkgsCross.musl64;
          };
          "aarch64-linux" = {
            target = "aarch64-unknown-linux-musl";
            crossPkgs = pkgs.pkgsCross.aarch64-multiplatform-musl;
          };
        };
        hasMusl = builtins.hasAttr system muslTargets;
        muslTarget = if hasMusl then muslTargets.${system}.target else null;
        muslCc = if hasMusl then muslTargets.${system}.crossPkgs.stdenv.cc else null;

        rustToolchain = pkgs.fenix.fromToolchainFile {
          file = ./rust-toolchain.toml;
          # Run with lib.fakeSha256 first to get the real hash from the error message
          sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        src = craneLib.cleanCargoSource ./.;

        commonArgs =
          {
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
          }
          // lib.optionalAttrs hasMusl {
            CARGO_BUILD_TARGET = muslTarget;
            CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";
            "CARGO_TARGET_${lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] muslTarget)}_LINKER" =
              "${muslCc}/bin/${muslCc.targetPrefix}cc";
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
            stdenv.cc
          ];
        };
      }
    );
}
