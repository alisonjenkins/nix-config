{ inputs, ... }: {
  imports = [ ];

  perSystem = { pkgs, system, ... }: {
    _module.args = {
      pkgsUnfree = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    };
  };
}
