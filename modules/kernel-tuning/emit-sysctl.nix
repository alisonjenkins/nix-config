{ lib, active }:
{
  boot.kernel.sysctl = lib.mkMerge (map (k: k.sysctls) (lib.attrValues active));
}
