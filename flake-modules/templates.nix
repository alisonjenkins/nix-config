{ ... }: {
  flake.templates = {
    rust = {
      description = "A Rust flake template with Rust Overlay and devshell setup.";
      path = ../templates/rust;
    };
  };
}
