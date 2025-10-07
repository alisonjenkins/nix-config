{
  perSystem = {pkgs, inputs, ...}: {
    packages.default =
    let
        naersk' = pkgs.callPackage inputs.naersk {};
    in {
      packages.default = naersk'.buildPackage {
        src = ./.;
      };
    };
  };
}
