{ lib, active }:
{
  boot.blacklistedKernelModules = lib.concatMap (k: k.blacklistedModules) (lib.attrValues active);
}
