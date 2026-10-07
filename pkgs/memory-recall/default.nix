{ lib, rustPlatform }:

# Builds scripts/retrieval-eval, which holds both the retrieval-eval harness and
# the memory-recall hook binary. The fileset keeps a local `target/` and the
# query sets out of the source, so they never invalidate the build.
rustPlatform.buildRustPackage {
  pname = "memory-recall";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../../scripts/retrieval-eval;
    fileset = lib.fileset.unions [
      ../../scripts/retrieval-eval/Cargo.toml
      ../../scripts/retrieval-eval/Cargo.lock
      ../../scripts/retrieval-eval/src
      ../../scripts/retrieval-eval/tests
    ];
  };
  cargoLock.lockFile = ../../scripts/retrieval-eval/Cargo.lock;

  # The tests drive a fake embeddings server over loopback, which the build
  # sandbox allows.
  doCheck = true;

  meta = {
    description = "Semantic recall of Claude memory files via a local embedding server, plus the harness that scores it";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "memory-recall";
  };
}
