{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "update-policy";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./src ./tests ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  # Unit and CLI tests are hermetic (temp dirs only), so the build runs them.
  doCheck = true;

  meta = {
    description = "Deterministic checks for docs/update-policy.md: a trust tier for every flake input and GitHub Action";
    license = lib.licenses.mit;
    mainProgram = "update-policy";
  };
}
