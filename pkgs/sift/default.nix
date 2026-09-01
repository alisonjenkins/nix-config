{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "sift";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # Reduction-engine and response-parsing tests are pure-logic, no
  # network access needed at build time.
  doCheck = true;

  # auth.rs discovers secretspec.toml here when running as an installed
  # binary (cwd-based discovery alone only works from a checkout of
  # this repo) — see resolve_secrets() and
  # docs/adr/0006-secretspec-credential-resolution.md.
  postInstall = ''
    install -Dm444 secretspec.toml $out/share/sift/secretspec.toml
  '';

  meta = {
    description = "Reduces Grafana LGTM (Loki/Prometheus/Mimir) observability output before it reaches an LLM context";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "sift";
  };
}
