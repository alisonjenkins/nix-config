{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "sift";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # Reduction-engine and response-parsing tests are pure-logic, no
  # network access needed at build time.
  doCheck = true;

  meta = {
    description = "Reduces Grafana LGTM (Loki/Prometheus/Mimir) observability output before it reaches an LLM context";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "sift";
  };
}
