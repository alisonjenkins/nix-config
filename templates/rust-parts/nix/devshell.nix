{
  perSystem = { pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
        cargo
        rustc
      ];

      shellHook = ''
        echo "Welcome to the development shell for mypackage!"
      '';
    };
  };
}
