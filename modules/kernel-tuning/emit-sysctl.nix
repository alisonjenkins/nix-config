{ lib, active }:
{
  boot.kernel.sysctl = lib.mkMerge (map
    (k: lib.mapAttrs (_: lib.mkOverride k.sysctlPriority) k.sysctls)
    (lib.attrValues active));
}
