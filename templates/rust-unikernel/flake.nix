{
  description = "A Rust unikernel project with NanoVMs/ops and AWS AMI deployment";

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

        # Build latest ops from source (nixpkgs version is outdated)
        ops-latest = pkgs.buildGoModule rec {
          pname = "ops";
          version = "0.1.45";

          src = pkgs.fetchFromGitHub {
            owner = "nanovms";
            repo = "ops";
            rev = version;
            hash = "sha256-gqBcJ4gXm48zfxGe7rRoFvRKe8jCeaNUjlc+IoGU3v4=";
          };

          vendorHash = "sha256-LHpj3FR4skOn5Z6SQJHMdkWlVGntOK2Y+8gBaHKjBOE=";
          proxyVendor = true;

          nativeBuildInputs = with pkgs; [
            buf
            protobuf
            protoc-gen-go
            protoc-gen-go-grpc
            grpc-gateway
          ];

          preBuild = ''
            export HOME=$(mktemp -d)
            buf generate --path ./protos/imageservice/imageservice.proto
            buf generate --path ./protos/instanceservice/instanceservice.proto
            buf generate --path ./protos/volumeservice/volumeservice.proto
          '';

          ldflags = [
            "-s"
            "-w"
            "-X github.com/nanovms/ops/lepton.Version=${version}"
          ];

          doCheck = false;

          meta = {
            description = "Build and run nanos unikernels";
            homepage = "https://github.com/nanovms/ops";
            license = lib.licenses.mit;
            platforms = lib.platforms.linux;
            mainProgram = "ops";
          };
        };

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
              ops-latest
              qemu
            ];
        };
      }
    );
}
