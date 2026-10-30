{ lib, config, cfg, active, skipped, kernelVersion }:
let
  # Parameters that legitimately repeat with different values.
  repeatable = [ "console" ];

  conflictPairs = lib.unique (lib.concatMap
    (a: map (b: lib.sort lib.lessThan [ a b ])
      (lib.filter (b: active ? ${b}) active.${a}.conflictsWith))
    (lib.attrNames active));

  paramKey = p: lib.head (lib.splitString "=" p);
  paramValue = p: lib.removePrefix "${paramKey p}=" p;
  collisions = lib.filterAttrs
    (key: values: !(lib.elem key repeatable) && lib.length values > 1)
    (lib.mapAttrs (_: ps: lib.unique (map paramValue ps))
      (lib.groupBy paramKey config.boot.kernelParams));
in
{
  assertions =
    map
      (pair: {
        assertion = false;
        message = "modules.kernelTuning: knobs ${lib.elemAt pair 0} and ${lib.elemAt pair 1} conflict";
      })
      conflictPairs
    ++ lib.mapAttrsToList
      (key: values: {
        assertion = false;
        message = "boot.kernelParams sets ${key} to more than one value: ${lib.concatStringsSep ", " values}";
      })
      collisions
    ++ [
      {
        assertion = cfg.lockdown == null || config.boot.resumeDevice == "";
        message = "modules.kernelTuning.lockdown blocks hibernation, but boot.resumeDevice is set";
      }
    ];

  warnings = lib.mapAttrsToList
    (name: k: "modules.kernelTuning.${name} needs kernel ${k.minKernel} or newer, this host runs ${kernelVersion}; the knob is skipped")
    skipped
  ++ lib.optional (cfg.lockdown != null && config.boot.extraModulePackages != [ ]) ''
    modules.kernelTuning.lockdown is set and boot.extraModulePackages is not empty:
    the kernel rejects out-of-tree modules that are not signed, and NixOS does not sign them.
  '';
}
