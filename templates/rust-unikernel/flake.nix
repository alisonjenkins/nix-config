{
  description = "A Rust unikernel project with NanoVMs/ops and AWS AMI deployment";

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

        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        src = craneLib.cleanCargoSource ./.;

        commonArgs =
          {
            inherit src;
            strictDeps = true;

            buildInputs =
              [
                # Add additional build inputs here
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

        my-crate = craneLib.buildPackage (
          commonArgs
          // {
            inherit cargoArtifacts;
            doCheck = false;
          }
        );
      in
      {
        checks = {
          inherit my-crate;

          my-crate-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );

          my-crate-doc = craneLib.cargoDoc (
            commonArgs
            // {
              inherit cargoArtifacts;
            }
          );

          my-crate-fmt = craneLib.cargoFmt {
            inherit src;
          };

          my-crate-nextest = craneLib.cargoNextest (
            commonArgs
            // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
              cargoNextestExtraArgs = "--no-tests=warn";
            }
          );
        };

        packages = {
          default = my-crate;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = my-crate;
        };

        devShells.default = craneLib.devShell {
          checks = self.checks.${system};

          packages =
            with pkgs;
            [
              bacon
              cargo-edit
              cargo-expand
              cargo-nextest
              cargo-watch
              just
              awscli2
              stdenv.cc
            ]
            ++ lib.optionals pkgs.stdenv.isLinux [
              ops
              qemu
            ];
        };
      }
    );
}
