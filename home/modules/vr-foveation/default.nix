# Per-game foveation profiles for the patched DXVK (spec 005). Generates the
# DXVK config file only; it does not edit Steam launch options or install the
# compat tool.
{ config, lib, ... }:
let
  cfg = config.modules.vrFoveation;
  inherit (lib) mkOption mkEnableOption mkIf types;

  rates = [ "1x1" "2x1" "1x2" "2x2" ];

  bandType = types.submodule {
    options = {
      radius = mkOption {
        # an integer literal such as `1` is a valid radius
        type = types.either types.int types.float;
        apply = r: r + 0.0;
        description = "Outer radius of this band as a fraction of the half-width, in (0, 1].";
      };
      rate = mkOption {
        type = types.enum rates;
        description = "Shading rate applied out to this radius.";
      };
    };
  };

  gameType = types.submodule {
    options = {
      enabled = mkOption {
        type = types.bool;
        default = false;
        description = "Whether foveation is allowed for this game.";
      };
      match = {
        minWidth = mkOption { type = types.nullOr types.int; default = null; description = "Minimum eye-target width in pixels."; };
        minHeight = mkOption { type = types.nullOr types.int; default = null; description = "Minimum eye-target height in pixels."; };
        width = mkOption { type = types.nullOr types.int; default = null; description = "Exact eye-target width in pixels."; };
        height = mkOption { type = types.nullOr types.int; default = null; description = "Exact eye-target height in pixels."; };
        layers = mkOption { type = types.nullOr types.int; default = null; description = "Exact array layer count."; };
        format = mkOption { type = types.nullOr types.str; default = null; description = "Vulkan format name, e.g. R8G8B8A8_SRGB."; };
        samples = mkOption { type = types.nullOr (types.enum [ 1 2 4 ]); default = null; description = "Sample count."; };
      };
      region.bands = mkOption {
        type = types.listOf bandType;
        default = [
          { radius = 0.45; rate = "1x1"; }
          { radius = 1.0; rate = "2x2"; }
        ];
        description = ''
          Bands outward from the centre, radii strictly increasing. The first band is the
          full-quality centre and must be 1x1; each later band runs from the previous radius
          out to its own.
        '';
      };
      gaze.source = mkOption {
        type = types.enum [ "fixed" "synthetic" ];
        default = "fixed";
        description = "Gaze source.";
      };
    };
  };

  # toString prints floats with six decimals; trim to the shortest form, keeping one decimal.
  fmtFloat = f:
    let
      stripped = builtins.head (builtins.match "(.*[^0])0*" (toString f));
    in
    if lib.hasSuffix "." stripped then "${stripped}0" else stripped;

  fmtBand = b: "${fmtFloat b.radius}:${b.rate}";

  matchLines = m:
    lib.concatMap
      (k: lib.optional (m.${k} != null) "dxvk.foveation.match.${k} = ${toString m.${k}}")
      [ "minWidth" "minHeight" "width" "height" "layers" "format" "samples" ];

  gameSection = exe: g:
    lib.concatStringsSep "\n" ([ "[${exe}]" "dxvk.foveation.enabled = ${lib.boolToString g.enabled}" ]
      ++ matchLines g.match
      ++ [
        "dxvk.foveation.region.bands = ${lib.concatMapStringsSep "," fmtBand g.region.bands}"
        "dxvk.foveation.gaze.source = ${g.gaze.source}"
      ]) + "\n";

  gameAssertions = exe: g:
    let
      radii = map (b: b.radius) g.region.bands;
      increasing = lib.all (p: p.fst < p.snd) (lib.zipLists (lib.init radii) (lib.tail radii));
      nonEmpty = radii != [ ];
      mk = assertion: message: { inherit assertion; message = "modules.vrFoveation.games.\"${exe}\": ${message}"; };
    in
    [
      (mk nonEmpty "region.bands must contain at least one band.")
      (mk (!nonEmpty || lib.all (r: r > 0.0 && r <= 1.0) radii) "band radii must be within (0, 1].")
      (mk (!nonEmpty || increasing) "band radii must be strictly increasing.")
      (mk (!nonEmpty || (builtins.head g.region.bands).rate == "1x1") "the first band is the full-quality centre and must be 1x1.")
      (mk (g.match.minWidth == null || g.match.minWidth > 0) "match.minWidth must be positive.")
      (mk (g.match.minHeight == null || g.match.minHeight > 0) "match.minHeight must be positive.")
    ];
in
{
  options.modules.vrFoveation = {
    enable = mkEnableOption "generation of the DXVK foveation profile file";

    games = mkOption {
      type = types.attrsOf gameType;
      default = { };
      description = "Foveation profiles keyed by Windows executable name, e.g. \"Fallout4VR.exe\".";
    };

    configFile = mkOption {
      type = types.str;
      readOnly = true;
      default = "${config.xdg.configHome}/dxvk-foveation/dxvk.conf";
      description = ''
        Path of the generated DXVK config. Not set globally, so other Wine games are
        unaffected. Use it in a Steam launch option:
        `DXVK_FOVEATION=1 DXVK_CONFIG_FILE=<this path> %command%`.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = lib.concatLists (lib.mapAttrsToList gameAssertions cfg.games);

    xdg.configFile."dxvk-foveation/dxvk.conf".text =
      lib.concatStringsSep "\n" (lib.mapAttrsToList gameSection cfg.games);
  };
}
