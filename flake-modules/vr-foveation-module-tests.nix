# Evaluates the vr-foveation home module with a minimal stub of the
# home-manager options it touches and compares the generated DXVK config to
# golden text (spec 005, FR-003/FR-005/FR-014).
#   nix build .#checks.x86_64-linux.vr-foveation-module
{ self, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") (
      let
        stub = { lib, ... }: {
          options = {
            assertions = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = [ ]; };
            xdg.configHome = lib.mkOption { type = lib.types.str; default = "/home/test/.config"; };
            xdg.configFile = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule { options.text = lib.mkOption { type = lib.types.lines; }; });
              default = { };
            };
          };
        };

        evalWith = games: lib.evalModules {
          modules = [
            stub
            self.homeModules.vr-foveation
            { modules.vrFoveation = { enable = true; inherit games; }; }
          ];
        };

        confKey = "dxvk-foveation/dxvk.conf";
        textOf = games: (evalWith games).config.xdg.configFile.${confKey}.text;
        failedAssertions = games: builtins.filter (a: !a.assertion) (evalWith games).config.assertions;

        # True when evaluation throws (type rejection) or any assertion fails.
        rejects = games:
          let r = builtins.tryEval (builtins.deepSeq [ (textOf games) (failedAssertions games) ] (failedAssertions games));
          in !r.success || r.value != [ ];

        defaultsText = ''
          [Fallout4VR.exe]
          dxvk.foveation.enabled = false
          dxvk.foveation.region.bands = 0.45:1x1,1.0:2x2
          dxvk.foveation.gaze.source = fixed
        '';

        twoGamesText = ''
          [Alpha.exe]
          dxvk.foveation.enabled = true
          dxvk.foveation.region.bands = 0.45:1x1,1.0:2x2
          dxvk.foveation.gaze.source = fixed

          [Zeta.exe]
          dxvk.foveation.enabled = false
          dxvk.foveation.region.bands = 0.45:1x1,1.0:2x2
          dxvk.foveation.gaze.source = fixed
        '';

        integerRadiusText = ''
          [G.exe]
          dxvk.foveation.enabled = false
          dxvk.foveation.region.bands = 1.0:1x1
          dxvk.foveation.gaze.source = fixed
        '';

        fullMatchText = ''
          [Fallout4VR.exe]
          dxvk.foveation.enabled = true
          dxvk.foveation.match.minWidth = 1000
          dxvk.foveation.match.minHeight = 1100
          dxvk.foveation.match.width = 2016
          dxvk.foveation.match.height = 2240
          dxvk.foveation.match.layers = 1
          dxvk.foveation.match.format = R8G8B8A8_SRGB
          dxvk.foveation.match.samples = 4
          dxvk.foveation.region.bands = 0.3:1x1,0.6:2x1,1.0:2x2
          dxvk.foveation.gaze.source = synthetic
        '';

        cases = {
          "defaults" = textOf { "Fallout4VR.exe" = { }; } == defaultsText;
          "two games sorted by name" =
            textOf { "Zeta.exe" = { }; "Alpha.exe".enabled = true; } == twoGamesText;
          "all match keys" = textOf {
            "Fallout4VR.exe" = {
              enabled = true;
              match = {
                minWidth = 1000;
                minHeight = 1100;
                width = 2016;
                height = 2240;
                layers = 1;
                format = "R8G8B8A8_SRGB";
                samples = 4;
              };
              region.bands = [
                { radius = 0.3; rate = "1x1"; }
                { radius = 0.6; rate = "2x1"; }
                { radius = 1.0; rate = "2x2"; }
              ];
              gaze.source = "synthetic";
            };
          } == fullMatchText;
          "config file path" =
            (evalWith { }).config.modules.vrFoveation.configFile == "/home/test/.config/dxvk-foveation/dxvk.conf";
          "rejects non-increasing radii" = rejects {
            "G.exe".region.bands = [ { radius = 0.8; rate = "1x1"; } { radius = 0.5; rate = "2x2"; } ];
          };
          "rejects equal radii" = rejects {
            "G.exe".region.bands = [ { radius = 0.5; rate = "1x1"; } { radius = 0.5; rate = "2x2"; } ];
          };
          "rejects radius above 1" = rejects {
            "G.exe".region.bands = [ { radius = 0.5; rate = "1x1"; } { radius = 1.5; rate = "2x2"; } ];
          };
          "rejects empty bands" = rejects { "G.exe".region.bands = [ ]; };
          "rejects samples 8" = rejects { "G.exe".match.samples = 8; };
          "rejects unknown rate" = rejects {
            "G.exe".region.bands = [ { radius = 1.0; rate = "4x4"; } ];
          };
          # the first band is the full-quality centre, so it is the single place the centre is defined
          "rejects a first band that is not full rate" = rejects {
            "G.exe".region.bands = [ { radius = 0.4; rate = "2x2"; } { radius = 1.0; rate = "2x2"; } ];
          };
          "rejects the removed innerRadius option" = rejects { "G.exe".region.innerRadius = 0.5; };
          # integer literals are valid radii and print as floats
          "accepts an integer radius" =
            textOf { "G.exe".region.bands = [ { radius = 1; rate = "1x1"; } ]; } == integerRadiusText;
          "rejects non-positive minWidth" = rejects { "G.exe".match.minWidth = 0; };
          "rejects non-positive minHeight" = rejects { "G.exe".match.minHeight = -5; };
        };

        failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) cases);
      in
      {
        checks.vr-foveation-module =
          if failed == [ ]
          then pkgs.runCommand "vr-foveation-module" { } "touch $out"
          else throw "vr-foveation-module failing cases: ${lib.concatStringsSep "; " failed}";
      }
    );
}
