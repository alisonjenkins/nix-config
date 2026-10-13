{
  lib,
  rustPlatform,
  clippy,
  rustfmt,
}:

# Builds scripts/aquaero-ctl. No hook or CI step in this repository runs
# `cargo fmt` or clippy, so the check phase does, and a lint or format
# failure fails the build.
rustPlatform.buildRustPackage {
  pname = "aquaero-ctl";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../../scripts/aquaero-ctl;
    fileset = lib.fileset.difference ../../scripts/aquaero-ctl (
      lib.fileset.unions [
        (lib.fileset.maybeMissing ../../scripts/aquaero-ctl/target)
        ../../scripts/aquaero-ctl/flake.nix
        ../../scripts/aquaero-ctl/flake.lock
        ../../scripts/aquaero-ctl/.gitignore
      ]
    );
  };
  cargoLock.lockFile = ../../scripts/aquaero-ctl/Cargo.lock;

  doCheck = true;
  nativeCheckInputs = [
    clippy
    rustfmt
  ];
  preCheck = ''
    cargo fmt --check
    cargo clippy --all-targets -- -D warnings
  '';

  meta = {
    description = "Read and set the stored configuration of an Aquacomputer aquaero fan controller";
    license = lib.licenses.mit;
    mainProgram = "aquaero-ctl";
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
