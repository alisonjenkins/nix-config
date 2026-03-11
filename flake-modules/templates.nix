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
    go = {
      description = "Go project with CI checks and distroless container image";
      path = ../templates/go;
    };
    go-lambda = {
      description = "AWS Lambda Go project with distroless container image";
      path = ../templates/go-lambda;
    };
    python = {
      description = "Python project with ruff, pytest, and container image";
      path = ../templates/python;
    };
    python-lambda = {
      description = "AWS Lambda Python project with awslambdaric and container image";
      path = ../templates/python-lambda;
    };
    node = {
      description = "Node.js project with CI checks and container image";
      path = ../templates/node;
    };
    node-lambda = {
      description = "AWS Lambda Node.js project with container image";
      path = ../templates/node-lambda;
    };
    typescript = {
      description = "TypeScript project with CI checks and container image";
      path = ../templates/typescript;
    };
    typescript-lambda = {
      description = "AWS Lambda TypeScript project with container image";
      path = ../templates/typescript-lambda;
    };
  };
}
