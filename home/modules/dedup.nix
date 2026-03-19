{ osConfig ? null, lib, config, ... }:
let
  sysPackageNames =
    if osConfig != null
    then lib.genAttrs
      (map (p: p.pname or p.name or "") osConfig.environment.systemPackages)
      (_: true)
    else {};

  isInSystem = p: sysPackageNames ? ${p.pname or p.name or ""};
in {
  options.custom.homePackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [];
    description = ''
      Packages to install via home-manager that are automatically
      deduplicated against system packages on NixOS. Use this instead
      of home.packages for any package that might also appear in
      environment.systemPackages.
    '';
  };

  config.home.packages = builtins.filter (p: !isInSystem p) config.custom.homePackages;
}
