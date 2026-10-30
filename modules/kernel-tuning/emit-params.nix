{ lib, cfg, active }:
{
  boot.kernelParams =
    lib.optional (cfg.lockdown != null) "lockdown=${cfg.lockdown}"
    ++ lib.concatMap (k: k.params) (lib.attrValues active);
}
