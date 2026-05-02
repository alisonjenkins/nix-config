{ inputs, ... }: {
  perSystem = { system, pkgs, ... }: {
    devShells.default =
      let
        # Lazy shim: defers fetching the tool's closure until first invocation.
        # Adds ~200-400 ms of `nix run` eval overhead per call but keeps
        # heavy closures (nix-fast-build pulls in 1.5 GB) out of the
        # direnv-cached profile, so `cd` into the repo stays fast.
        lazy = bin: nixpkgsAttr: pkgs.writeShellScriptBin bin ''
          exec nix run nixpkgs#${nixpkgsAttr} -- "$@"
        '';
      in
      pkgs.mkShellNoCC {
        packages = (with inputs.nixpkgs.legacyPackages.${system}; [
          age
          just
          pv
          sops
          ssh-to-age
        ]) ++ [
          (lazy "crane" "go-containerregistry")
          (lazy "deploy" "deploy-rs")
          (lazy "nix-fast-build" "nix-fast-build")
          (lazy "nixos-anywhere" "nixos-anywhere")
          (lazy "secret-tool" "libsecret")
          (lazy "skopeo" "skopeo")
          (lazy "uplosi" "uplosi")
        ];
      };
  };
}
