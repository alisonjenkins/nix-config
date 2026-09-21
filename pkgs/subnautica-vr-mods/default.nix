# Payload directory tree, laid out exactly like a Subnautica install, meant
# to be synced on top of the Steam-managed game directory (which nix does not
# and cannot own — it's fetched and patched by Steam itself).
#
# SubmersedVR and the traditional VR Enhancements mod are upstream-documented
# as mutually exclusive (SubmersedVR replaces the VR Enhancements author's own
# assembly patches), so `mode` picks exactly one plugin set on top of the
# shared BepInEx.Subnautica loader pack both require.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  mode ? "submersed",
}:
let
  # toebeann/BepInEx.Subnautica — the doorstop + BepInEx core loader both mod
  # variants below inject through.
  bepinexPack = fetchurl {
    url = "https://github.com/toebeann/BepInEx.Subnautica/releases/download/v5.4.23-pack.3.1.1/Tobey.s.BepInEx.Pack.for.Subnautica.zip";
    sha256 = "0gnxlili0j1kbdaagpd7f5cwjmb0gx0gdwfc0p7sclr2q9pgv891";
  };

  # Okabintaro/SubmersedVR 0.2.0 — motion-controller VR mode. Ships a
  # BepInEx plugin plus replacement SteamVR.dll/SteamVR_Actions.dll and
  # controller binding JSON that overwrite the game's own copies.
  submersedVR = fetchurl {
    url = "https://github.com/Okabintaro/SubmersedVR/releases/download/0.2.0/SubmersedVR_0.2.0.zip";
    sha256 = "08ih9ga8pf2hqiqxnvqg5qgnggncglia8ca4gw8rmh4shr3a8hjd";
  };

  # IWhoI/SubnauticaVREnhancements v3.2.2 — comfort/QoL fixes for the
  # original gamepad/keyboard-driven native VR mode (HUD, PDA placement,
  # subtitles, cursor, walk speed).
  vrEnhancements = fetchurl {
    url = "https://github.com/IWhoI/SubnauticaVREnhancements/releases/download/v3.2.2/VR.Enhancements.v3.2.2.zip";
    sha256 = "0zpr3plj5gd70aj143x39xvb2maypna4367ig96pnwhva94ygl9y";
  };

  validModes = [
    "submersed"
    "enhancements"
  ];
in
assert lib.assertMsg (builtins.elem mode validModes)
  "subnautica-vr-mods: mode must be one of ${builtins.toJSON validModes}, got ${mode}";
stdenvNoCC.mkDerivation {
  pname = "subnautica-vr-mods-${mode}";
  version = "2026-09-21";

  dontUnpack = true;
  nativeBuildInputs = [ unzip ];

  installPhase =
    ''
      runHook preInstall

      mkdir -p "$out"
      unzip -q ${bepinexPack} -d "$out"
    ''
    + (
      if mode == "submersed" then
        ''
          # Overlays onto the BepInEx pack: adds BepInEx/plugins/SubmersedVR.dll
          # and overwrites the game's own SteamVR.dll/SteamVR_Actions.dll and
          # controller binding JSON with SubmersedVR's replacements.
          unzip -oq ${submersedVR} -d "$out"
        ''
      else
        ''
          mkdir -p "$out/BepInEx/plugins"
          unzip -p ${vrEnhancements} '*/VREnhancements.dll' > "$out/BepInEx/plugins/VREnhancements.dll"
        ''
    )
    + ''
      runHook postInstall
    '';

  meta = {
    description = "Subnautica VR mod payload (BepInEx + ${mode}), synced onto a Steam-managed install";
    homepage =
      if mode == "submersed" then
        "https://github.com/Okabintaro/SubmersedVR"
      else
        "https://github.com/IWhoI/SubnauticaVREnhancements";
    license = lib.licenses.unfree; # redistributes third-party mod binaries verbatim
    platforms = lib.platforms.all;
  };
}
