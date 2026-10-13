# Evaluates the hardware-aquaero-ctl module with a minimal stub of the NixOS
# options it touches: a bad value must fail the build with a message naming it
# (spec 008, FR-016), and the generated service must follow the mode.
#   nix build .#checks.x86_64-linux.aquaero-ctl-module
{ self, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") (
      let
        stub = { lib, ... }: {
          options = {
            assertions = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = [ ]; };
            environment.systemPackages = lib.mkOption { type = lib.types.listOf lib.types.raw; default = [ ]; };
            users.users = lib.mkOption { type = lib.types.attrsOf lib.types.raw; default = { }; };
            users.groups = lib.mkOption { type = lib.types.attrsOf lib.types.raw; default = { }; };
            systemd.tmpfiles.rules = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
            systemd.services = lib.mkOption { type = lib.types.attrsOf lib.types.raw; default = { }; };
            services.udev.packages = lib.mkOption { type = lib.types.listOf lib.types.raw; default = [ ]; };
          };
        };

        point = temp: percent: { inherit temp percent; };
        good = {
          "4" = {
            sensor = 1;
            minPercent = 30;
            points = [ (point 30 30) (point 45 100) ];
          };
        };

        evalWith = extra: lib.evalModules {
          modules = [
            stub
            { _module.args.pkgs = pkgs; }
            self.nixosModules.hardware-aquaero-ctl
            { hardware.aquaeroCtl = { enable = true; package = pkgs.hello; } // extra; }
          ];
        };

        failed = extra: builtins.filter (a: !a.assertion) (evalWith extra).config.assertions;
        # True when some failed assertion's message contains `needle`.
        rejectsWith = needle: fans:
          builtins.any (a: lib.hasInfix needle a.message) (failed { inherit fans; });
        execStart = extra: (evalWith extra).config.systemd.services.aquaero-ctl-apply.serviceConfig.ExecStart;
        withFan = changes: { "4" = good."4" // changes; };

        cases = {
          "a valid curve passes every assertion" = failed { fans = good; } == [ ];
          "apply mode has no --check" = !(lib.hasInfix "--check" (execStart { fans = good; }));
          "check mode adds --check" = lib.hasInfix "--check" (execStart { fans = good; mode = "check"; });
          "the service runs the apply command" = lib.hasInfix " apply --desired " (execStart { fans = good; });
          "no fan is rejected" = rejectsWith "at least one fan" { };
          "a minimum above 100 names the value" = rejectsWith "101 is outside 0 to 100" (withFan { minPercent = 101; });
          "a negative minimum is rejected" = rejectsWith "-1 is outside 0 to 100" (withFan { minPercent = -1; });
          "one point is rejected" = rejectsWith "at least 2 points, got 1" (withFan { points = [ (point 30 30) ]; });
          "too many points are rejected" = rejectsWith "at most 16 points, got 17" (withFan {
            points = builtins.genList (i: point (20 + i) (40 + i)) 17;
          });
          "equal temperatures are rejected naming them" =
            rejectsWith "temperature 30 does not rise above the previous point's 30"
              (withFan { points = [ (point 30 30) (point 30 50) ]; });
          "decreasing temperatures are rejected" =
            rejectsWith "temperature 35 does not rise above the previous point's 40"
              (withFan { points = [ (point 40 30) (point 35 50) ]; });
          "a point below the minimum is rejected" =
            rejectsWith "percent 25 at 30 °C is below minPercent 30"
              (withFan { points = [ (point 30 25) (point 45 100) ]; });
          "a decreasing percent is rejected" =
            rejectsWith "percent 40 is below the previous point's 50"
              (withFan { points = [ (point 30 50) (point 45 40) ]; });
          "a percent above 100 is rejected" =
            rejectsWith "percent 120 is above 100" (withFan { points = [ (point 30 30) (point 45 120) ]; });
          "another fan is not supported" = rejectsWith "fan 2 is not supported" { "2" = good."4"; };
          "another sensor is not supported" = rejectsWith "sensor 3 is not supported" (withFan { sensor = 3; });
        };

        failedCases = lib.attrNames (lib.filterAttrs (_: ok: !ok) cases);
      in
      {
        checks.aquaero-ctl-module =
          if failedCases == [ ]
          then pkgs.runCommand "aquaero-ctl-module" { } "touch $out"
          else throw "aquaero-ctl-module failing cases: ${lib.concatStringsSep "; " failedCases}";
      }
    );
}
