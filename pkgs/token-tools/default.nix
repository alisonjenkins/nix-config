{ lib, rustPlatform }:

# Builds scripts/token-tools: cc-obs-ledger (Claude Code hook tool) and
# cc-obs-query (query CLI over the local observability stack). The fileset
# keeps a local `target/` out of the source.
rustPlatform.buildRustPackage {
  pname = "token-tools";
  version = "0.1.0";

  # The repo root is the source root because a cc-obs-query test reads the shipped
  # question pack from docs/token-efficiency.
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../scripts/token-tools/Cargo.toml
      ../../scripts/token-tools/Cargo.lock
      ../../scripts/token-tools/cc-obs-ledger
      ../../scripts/token-tools/cc-obs-query
      ../../docs/token-efficiency/questions.yaml
    ];
  };
  sourceRoot = "source/scripts/token-tools";
  cargoLock.lockFile = ../../scripts/token-tools/Cargo.lock;

  doCheck = true;
  # Without this the macOS sandbox refuses tests that use a loopback server.
  __darwinAllowLocalNetworking = true;

  meta = {
    description = "Hook tool and query CLI for token-spend telemetry from Claude Code";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
