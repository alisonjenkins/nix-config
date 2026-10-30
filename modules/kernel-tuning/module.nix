# The mechanism, parameterised by the knob table so the checks can feed it a
# test table. `default.nix` applies it to the real table.
{ knobs, profiles ? { } }:
{ config, lib, ... }:
let
  cfg = config.modules.kernelTuning;

  withDefaults = k: {
    params = [ ];
    sysctls = { };
    blacklistedModules = [ ];
    minKernel = null;
    conflictsWith = [ ];
  } // k;

  table = lib.mapAttrs (_: withDefaults) knobs;

  selected = lib.concatMap (p: profiles.${p}) cfg.profiles;

  kernelVersion = config.boot.kernelPackages.kernel.version;
  supported = k: k.minKernel == null || lib.versionAtLeast kernelVersion k.minKernel;

  enabled = lib.filterAttrs (name: _: cfg.${name}) table;
  active = lib.filterAttrs (_: supported) enabled;
  skipped = lib.filterAttrs (_: k: !supported k) enabled;
in
{
  options.modules.kernelTuning = lib.mapAttrs
    (_: k: lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "${k.category} knob, cost ${k.cost}. Breaks: ${k.breaks}.";
    })
    table
  // {
    profiles = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames profiles));
      default = [ ];
      description = ''
        Named knob sets to enable. A profile only sets its knobs to true at
        default priority, so a host switches one off with a plain
        `modules.kernelTuning.<knob> = false`.
      '';
    };

    lockdown = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "integrity" ]);
      default = null;
      description = ''
        Kernel lockdown mode. "integrity" blocks hibernation and rejects
        unsigned out-of-tree modules, which NixOS does not sign by default.
        Value-typed, so it is never part of a profile.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # Keys come from the static table: a key set that depends on
      # cfg.profiles would recurse through the module system.
      modules.kernelTuning = lib.mapAttrs
        (name: _: lib.mkIf (lib.elem name selected) (lib.mkDefault true))
        table;
    }
    (import ./emit-params.nix { inherit lib cfg active; })
    (import ./emit-sysctl.nix { inherit lib active; })
    (import ./emit-modules.nix { inherit lib active; })
    (import ./guards.nix { inherit lib config cfg active skipped kernelVersion; })
  ];
}
