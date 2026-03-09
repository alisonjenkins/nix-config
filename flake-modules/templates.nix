{ ... }: {
  flake.templates = {
    rust = {
      description = "Rust project with crane, rust-overlay, CI checks, and distroless container image";
      path = ../templates/rust;
    };
    rust-lambda = {
      description = "AWS Lambda Rust project with crane, cargo-lambda, and distroless container image";
      path = ../templates/rust-lambda;
    };
  };
}
