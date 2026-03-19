{ osConfig ? null, lib, config, ... }:
let
  hasSysConfig = osConfig != null;

  sysPackageNames =
    if hasSysConfig
    then lib.genAttrs
      (map (p: p.pname or p.name or "") osConfig.environment.systemPackages)
      (_: true)
    else {};

  isInSystem = p: sysPackageNames ? ${p.pname or p.name or ""};
in {
  # Apply a dedup filter to the home.packages option. The `apply` function
  # runs after all module definitions are merged, so it catches packages
  # added by programs.* modules too. On non-NixOS (standalone HM, Darwin),
  # the filter is a no-op.
  options.home.packages = lib.mkOption {
    apply = pkgs:
      if hasSysConfig
      then builtins.filter (p: !isInSystem p) pkgs
      else pkgs;
  };
}
