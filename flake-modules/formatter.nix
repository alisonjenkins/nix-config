{ ... }: {
  # Define `formatter` for every system. Besides giving `nix fmt` a real
  # tool, an explicit per-system value lets flake-parts statically prove
  # the output is non-null on all systems — without it, `nix flake check`
  # trips the "could not determine statically that no formatter is defined
  # for *all* systems" heuristic error.
  perSystem = { pkgs, ... }: {
    formatter = pkgs.nixfmt-rfc-style;
  };
}
