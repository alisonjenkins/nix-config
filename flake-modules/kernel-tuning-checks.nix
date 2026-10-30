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

      profiles = import (self + "/modules/kernel-tuning/profiles.nix");
      norm = k: { params = [ ]; sysctls = { }; } // k;
      expectedParams = members: lib.sort lib.lessThan (lib.unique
        (lib.concatMap (n: (norm knobs.${n}).params) members));
      expectedSysctls = members:
        lib.foldl' (acc: n: acc // (norm knobs.${n}).sysctls) { } members;
      withProfiles = ps: evalWith { modules.kernelTuning.profiles = ps; };
      emitsExactly = c: members:
        lib.sort lib.lessThan (addedParams c) == expectedParams members
        && lib.getAttrs (lib.attrNames (expectedSysctls members)) (sysctlOf c) == expectedSysctls members
        && removeAttrs (sysctlOf c) (lib.attrNames (expectedSysctls members))
        == removeAttrs (sysctlOf baseline) (lib.attrNames (expectedSysctls members));

      profileCase = name: {
        name = "profile ${name} alone emits exactly its members";
        ok = emitsExactly (withProfiles [ name ]) profiles.${name};
      };

      hostOverride = evalWith {
        modules.kernelTuning.profiles = [ "hardened-workstation" ];
        modules.kernelTuning.initOnAlloc = false;
      };

      failedAsserts = c: map (a: a.message) (lib.filter (a: !a.assertion) c.config.assertions);
      mentionsAll = words: msgs:
        lib.any (m: lib.all (w: lib.hasInfix w m) words) msgs;

      conflicting = evalWith (enable [ "mitigationsOff" "nosmt" ]);
      collidingHost = evalWith {
        modules.kernelTuning.iommuIsolation = true;
        boot.kernelParams = [ "amd_iommu=off" ];
      };
      repeatedSameValue = evalWith {
        modules.kernelTuning.initOnAlloc = true;
        boot.kernelParams = [ "init_on_alloc=1" ];
      };
      hibernating = evalWith {
        modules.kernelTuning.lockdown = "integrity";
        boot.resumeDevice = "/dev/disk/by-label/swap";
      };
      lockedDown = evalWith { modules.kernelTuning.lockdown = "integrity"; };
      withExtraModule = evalWith ({ config, ... }: {
        modules.kernelTuning.lockdown = "integrity";
        boot.extraModulePackages = [ config.boot.kernelPackages.evdi ];
      });

      versioned = evalModules
        (mechanism {
          knobs = {
            futureKnob = {
              category = "security";
              params = [ "future_param=1" ];
              sysctls."fake.future" = 1;
              blacklistedModules = [ "future_module" ];
              minKernel = "99.0";
              cost = "none";
              breaks = "nothing";
              conflictsWith = [ "oldKnob" ];
            };
            oldKnob = {
              category = "security";
              params = [ "old_param=1" ];
              minKernel = "1.0";
              cost = "none";
              breaks = "nothing";
            };
          };
        })
        { modules.kernelTuning = { futureKnob = true; oldKnob = true; }; };

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

      cases = map knobCase (lib.attrNames knobs) ++ map profileCase (lib.attrNames profiles) ++ [
        {
          # Membership is policy, and profileCase derives its expectation from
          # profiles.nix, so pin the lists here to catch an unintended edit.
          name = "profile membership matches the pinned lists";
          ok =
            let
              pinned = {
                hardened-workstation = [ "debugfsOff" "initOnAlloc" "kexecDisable" "kstackRandomize" "noVsyscall" "pageShuffle" "slabNomerge" ];
                hardened-server = [ "debugfsOff" "initOnAlloc" "kexecDisable" "kstackRandomize" "noVsyscall" "pageShuffle" "slabNomerge" ];
                gaming = [ "compactionProactivenessOff" "maxMapCountHigh" "splitLockMitigateOff" ];
              };
            in
            lib.attrNames profiles == lib.attrNames pinned
            && lib.all (n: lib.sort lib.lessThan profiles.${n} == pinned.${n}) (lib.attrNames pinned);
        }
        {
          name = "every profile member is a table knob";
          ok = lib.all (n: knobs ? ${n}) (lib.concatLists (lib.attrValues profiles));
        }
        {
          name = "no profile enables lockdown or a conflicting pair";
          ok = lib.all
            (members: lib.all (n: lib.all (o: !(lib.elem o members)) (knobs.${n}.conflictsWith or [ ]))
              members)
            (lib.attrValues profiles);
        }
        {
          name = "hardened-workstation and gaming compose as a union";
          ok = emitsExactly (withProfiles [ "hardened-workstation" "gaming" ])
            (profiles.hardened-workstation ++ profiles.gaming);
        }
        {
          name = "gaming profile sets vm.max_map_count";
          ok = (sysctlOf (withProfiles [ "gaming" ])).${"vm.max_map_count"} == 2147483642;
        }
        {
          name = "hardened-workstation leaves out initOnFree";
          ok = !(lib.elem "init_on_free=1" (paramsOf (withProfiles [ "hardened-workstation" ])));
        }
        {
          name = "host initOnAlloc = false beats the profile without mkForce";
          ok = !(lib.elem "init_on_alloc=1" (paramsOf hostOverride))
            && lib.elem "slab_nomerge" (paramsOf hostOverride);
        }
        {
          name = "conflictsWith is symmetric across the table";
          ok = lib.all
            (a: lib.all (b: lib.elem a (knobs.${b}.conflictsWith or [ ])) (knobs.${a}.conflictsWith or [ ]))
            (lib.attrNames knobs);
        }
        {
          name = "mitigationsOff with nosmt asserts, naming both";
          ok = mentionsAll [ "mitigationsOff" "nosmt" ] (failedAsserts conflicting);
        }
        {
          name = "a declared conflict is reported once";
          ok = lib.length (failedAsserts conflicting) == 1;
        }
        {
          name = "no assertion on an empty host or on any profile";
          ok = failedAsserts baseline == [ ]
            && lib.all (p: failedAsserts (withProfiles [ p ]) == [ ]) (lib.attrNames profiles)
            && failedAsserts (withProfiles (lib.attrNames profiles)) == [ ];
        }
        {
          name = "iommuIsolation against a host amd_iommu=off is flagged";
          ok = mentionsAll [ "amd_iommu" "force_isolation" "off" ] (failedAsserts collidingHost);
        }
        {
          name = "the same param twice with one value is not a collision";
          ok = failedAsserts repeatedSameValue == [ ];
        }
        {
          name = "lockdown with resumeDevice asserts";
          ok = mentionsAll [ "lockdown" "resumeDevice" ] (failedAsserts hibernating);
        }
        {
          name = "lockdown without resumeDevice does not assert or warn";
          ok = failedAsserts lockedDown == [ ] && lockedDown.config.warnings == [ ];
        }
        {
          name = "lockdown with extraModulePackages warns";
          ok = mentionsAll [ "lockdown" "extraModulePackages" ] withExtraModule.config.warnings;
        }
        {
          name = "a knob above the kernel version warns, naming the knob";
          ok = mentionsAll [ "futureKnob" "99.0" ] versioned.config.warnings;
        }
        {
          name = "a knob above the kernel version emits nothing";
          ok = !(lib.elem "future_param=1" (paramsOf versioned))
            && !(versioned.config.boot.kernel.sysctl ? "fake.future")
            && !(lib.elem "future_module" versioned.config.boot.blacklistedKernelModules);
        }
        {
          name = "a knob within the kernel version still emits, and a skipped conflict does not assert";
          ok = lib.elem "old_param=1" (paramsOf versioned) && failedAsserts versioned == [ ];
        }
        {
          name = "no real knob is skipped on the default kernel";
          ok = (evalWith (enable (lib.attrNames knobs))).config.warnings == [ ];
        }
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
