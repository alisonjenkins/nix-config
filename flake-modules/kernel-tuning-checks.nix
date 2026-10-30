# Eval check for modules/kernel-tuning: knobs emit the expected kernel params,
# sysctls and module blacklists, and the guard rails fire.
# Run with: nix build .#checks.<system>.kernel-tuning --no-link
{ self, inputs, ... }:
{
  perSystem = { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      knobs = import (self + "/modules/kernel-tuning/knobs.nix");
      mechanism = import (self + "/modules/kernel-tuning/module.nix");

      evalModules = tuningModule: extra: inputs.nixpkgs.lib.nixosSystem {
        modules = [
          tuningModule
          {
            nixpkgs.hostPlatform = system;
            system.stateVersion = "25.05";
            fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
            boot.loader.grub.enable = false;
          }
          extra
        ];
      };
      evalWith = evalModules self.nixosModules.kernel-tuning;

      baseline = evalWith { };
      paramsOf = c: c.config.boot.kernelParams;
      sysctlOf = c: c.config.boot.kernel.sysctl;
      addedParams = c: lib.subtractLists (paramsOf baseline) (paramsOf c);
      enable = names: { modules.kernelTuning = lib.genAttrs names (_: true); };

      # A knob alone adds exactly its own params and sysctls, nothing else.
      knobCase = name:
        let
          k = { params = [ ]; sysctls = { }; } // knobs.${name};
          c = evalWith (enable [ name ]);
          keys = lib.attrNames k.sysctls;
        in
        {
          name = "knob ${name} emits exactly its own settings";
          ok = lib.sort lib.lessThan (addedParams c) == lib.sort lib.lessThan k.params
            && lib.getAttrs keys (sysctlOf c) == k.sysctls
            && removeAttrs (sysctlOf c) keys == removeAttrs (sysctlOf baseline) keys;
        };

      withBlacklist = evalModules
        (mechanism {
          knobs.fakeModuleOff = {
            category = "hardware";
            blacklistedModules = [ "fake_test_module" ];
            cost = "none";
            breaks = "nothing";
          };
        })
        { modules.kernelTuning.fakeModuleOff = true; };

      cases = map knobCase (lib.attrNames knobs) ++ [
        {
          name = "initOnAlloc emits init_on_alloc=1";
          ok = lib.elem "init_on_alloc=1" (paramsOf (evalWith (enable [ "initOnAlloc" ])));
        }
        {
          name = "maxMapCountHigh sets vm.max_map_count";
          ok = (sysctlOf (evalWith (enable [ "maxMapCountHigh" ]))).${"vm.max_map_count"} == 2147483642;
        }
        {
          name = "noSysrq is only kernel.sysrq = 0";
          ok = (sysctlOf (evalWith (enable [ "noSysrq" ]))).${"kernel.sysrq"} == 0
            && addedParams (evalWith (enable [ "noSysrq" ])) == [ ];
        }
        {
          name = "defaults emit none of the table's params";
          ok = lib.all (k: lib.all (p: !(lib.elem p (paramsOf baseline))) (k.params or [ ]))
            (lib.attrValues knobs);
        }
        {
          name = "lockdown = integrity emits lockdown=integrity";
          ok = lib.elem "lockdown=integrity" (paramsOf (evalWith { modules.kernelTuning.lockdown = "integrity"; }));
        }
        {
          name = "lockdown defaults to off";
          ok = !(lib.any (lib.hasPrefix "lockdown=") (paramsOf baseline));
        }
        {
          name = "blacklistedModules reach boot.blacklistedKernelModules";
          ok = lib.elem "fake_test_module" withBlacklist.config.boot.blacklistedKernelModules
            && !(lib.elem "fake_test_module" baseline.config.boot.blacklistedKernelModules);
        }
      ];
      failures = map (c: c.name) (lib.filter (c: !c.ok) cases);
    in
    {
      checks.kernel-tuning = pkgs.runCommand "kernel-tuning" { } ''
        ${lib.optionalString (failures != [ ]) ''
          echo "failed: ${lib.concatStringsSep ", " failures}" >&2
          exit 1
        ''}
        touch $out
      '';
    };
}
