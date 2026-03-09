{ ... }: {
  flake.templates = {
    rust = {
      description = "Rust project with crane, rust-overlay, CI checks, and distroless container image";
      path = ../templates/rust;
    };
  };
}
