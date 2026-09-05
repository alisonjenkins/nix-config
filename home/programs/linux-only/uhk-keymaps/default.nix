{ config, lib, pkgs, ... }:

let
  cfg = config.programs.uhkKeymaps;

  # Everything from a real UHK Agent export except the HD2 keymap: your
  # existing Colemak/Dvorak/QWERTY keymaps and their macros, carried over
  # verbatim rather than reinvented in Nix -- they're static keyboard
  # layouts, not something a DSL buys anything for. The three macros that
  # type an email address have their text blanked out here; the real
  # values come back in via sops.templates below, never touching the
  # Nix store in plaintext.
  baseConfig = builtins.fromJSON (builtins.readFile ./base-user-config.json);

  qwr = lib.findFirst (k: k.abbreviation == "QWR") (throw "QWR keymap not found in base-user-config.json") baseConfig.keymaps;

  findLayer = keymap: id: lib.findFirst (l: l.id == id) (throw "layer ${id} not found") keymap.layers;
  findModule = layer: id: lib.findFirst (m: m.id == id) (throw "module ${toString id} not found") layer.modules;

  noneActions = n: lib.genList (_: { keyActionType = "none"; }) n;

  # Left-half (module 1) key index for each letter/digit, confirmed
  # empirically against a real export's QWR base layer scancodes.
  keyIndex = {
    "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6;
    Q = 8; W = 9; E = 10; R = 11; T = 12;
    A = 14; S = 15; D = 16; F = 17; G = 18;
    Z = 21; X = 22; C = 23; V = 24; B = 25;
  };

  scancode = { I = 12; J = 13; K = 14; L = 15; };
  leftCtrlMask = 1;
  holdMs = 100;
  gapMs = 100;

  # Holds LeftCtrl, presses/holds/releases each direction with a gap
  # between, then releases Ctrl -- a plain tap (press+release with no
  # controllable hold) was too brief for Helldivers 2 to register
  # reliably; this is the timing that actually worked on real hardware.
  mkDirectionMacro = name: code: {
    isLooped = false;
    isPrivate = false;
    inherit name;
    macroActions =
      [
        { macroActionType = "key"; action = "press"; modifierMask = leftCtrlMask; }
        { macroActionType = "delay"; delay = gapMs; }
      ]
      ++ lib.concatMap (dir: [
        { macroActionType = "key"; action = "press"; type = "basic"; scancode = scancode.${dir}; }
        { macroActionType = "delay"; delay = holdMs; }
        { macroActionType = "key"; action = "release"; type = "basic"; scancode = scancode.${dir}; }
        { macroActionType = "delay"; delay = gapMs; }
      ]) (lib.stringToCharacters code)
      ++ [ { macroActionType = "key"; action = "release"; modifierMask = leftCtrlMask; } ];
  };

  # (layer, key, stratagem name, I/J/K/L direction code) -- one entry per
  # Helldivers 2 stratagem, plus Reinforce. Codes confirmed against the
  # game's official wiki; key placement worked out live against the real
  # keyboard (see git log for the back-and-forth on ergonomics).
  stratagems = [
    # Fn: Orbitals + ship calls + Reinforce
    { layer = "fn"; key = "A"; name = "Orbital Precision Strike"; code = "LLI"; }
    { layer = "fn"; key = "G"; name = "Orbital Gatling Barrage"; code = "LKJII"; }
    { layer = "fn"; key = "B"; name = "Orbital Airburst Strike"; code = "LLL"; }
    { layer = "fn"; key = "X"; name = "Orbital Gas Strike"; code = "LLKL"; }
    { layer = "fn"; key = "E"; name = "Orbital EMS Strike"; code = "LLJK"; }
    { layer = "fn"; key = "S"; name = "Orbital Smoke Strike"; code = "LLKI"; }
    { layer = "fn"; key = "1"; name = "Orbital 120mm HE Barrage"; code = "LLKJLK"; }
    { layer = "fn"; key = "W"; name = "Orbital Walking Barrage"; code = "LKLKLK"; }
    { layer = "fn"; key = "3"; name = "Orbital 380mm HE Barrage"; code = "LKIIJKK"; }
    { layer = "fn"; key = "F"; name = "Orbital Napalm Barrage"; code = "LLKJLI"; }
    { layer = "fn"; key = "R"; name = "Orbital Laser"; code = "LKILK"; }
    { layer = "fn"; key = "Z"; name = "Orbital Railcannon Strike"; code = "LIKKL"; }
    { layer = "fn"; key = "D"; name = "Orbital Illumination Flare"; code = "LLJJ"; }
    { layer = "fn"; key = "C"; name = "Resupply"; code = "KKIL"; }
    { layer = "fn"; key = "Q"; name = "SOS Beacon"; code = "IKLI"; }
    { layer = "fn"; key = "V"; name = "Call In Super Destroyer"; code = "IIKKJLJL"; }
    { layer = "fn"; key = "T"; name = "Reinforce"; code = "IKLJI"; }
    # Fn2: Eagles + Sentries
    { layer = "fn2"; key = "R"; name = "Eagle Strafing Run"; code = "ILL"; }
    { layer = "fn2"; key = "A"; name = "Eagle Airstrike"; code = "ILKL"; }
    { layer = "fn2"; key = "S"; name = "Eagle Smoke Strike"; code = "ILIK"; }
    { layer = "fn2"; key = "F"; name = "Eagle Napalm Airstrike"; code = "ILKI"; }
    { layer = "fn2"; key = "1"; name = "Eagle 110mm Rocket Pods"; code = "ILIJ"; }
    { layer = "fn2"; key = "C"; name = "Eagle Cluster Bomb"; code = "ILKKL"; }
    { layer = "fn2"; key = "5"; name = "Eagle 500kg Bomb"; code = "ILKKK"; }
    { layer = "fn2"; key = "E"; name = "Eagle Rearm"; code = "IIJIL"; }
    { layer = "fn2"; key = "2"; name = "Eagle Gas Airstrike"; code = "ILJL"; }
    { layer = "fn2"; key = "G"; name = "MG Sentry"; code = "KILLI"; }
    { layer = "fn2"; key = "T"; name = "Gatling Sentry"; code = "KILJ"; }
    { layer = "fn2"; key = "Q"; name = "Autocannon Sentry"; code = "KILIJI"; }
    { layer = "fn2"; key = "B"; name = "Mortar Sentry"; code = "KILLK"; }
    { layer = "fn2"; key = "W"; name = "Rocket Sentry"; code = "KILLJ"; }
    { layer = "fn2"; key = "Z"; name = "Tesla Tower"; code = "KILIJL"; }
    { layer = "fn2"; key = "D"; name = "EMS Mortar Sentry"; code = "KILKL"; }
    { layer = "fn2"; key = "V"; name = "Laser Sentry"; code = "KILKIL"; }
    { layer = "fn2"; key = "3"; name = "Flame Sentry"; code = "KILKII"; }
    { layer = "fn2"; key = "X"; name = "Gas Mortar Sentry"; code = "KILKJ"; }
    { layer = "fn2"; key = "4"; name = "APW-1 Anti-Materiel Rifle"; code = "KJLIK"; }
    # Fn3: Support weapons, anti-armor/explosive
    { layer = "fn3"; key = "E"; name = "EAT-17 Expendable Anti-Tank"; code = "KKJIL"; }
    { layer = "fn3"; key = "R"; name = "GR-8 Recoilless Rifle"; code = "KJLLJ"; }
    { layer = "fn3"; key = "A"; name = "AC-8 Autocannon"; code = "KJKIIL"; }
    { layer = "fn3"; key = "S"; name = "FAF-14 Spear"; code = "KKIKK"; }
    { layer = "fn3"; key = "Q"; name = "LAS-99 Quasar Cannon"; code = "KKIJL"; }
    { layer = "fn3"; key = "B"; name = "RL-77 Airburst Rocket Launcher"; code = "KIIJL"; }
    { layer = "fn3"; key = "C"; name = "MLS-4X Commando"; code = "KJIKL"; }
    { layer = "fn3"; key = "G"; name = "S-11 Speargun"; code = "KLKJIL"; }
    { layer = "fn3"; key = "D"; name = "GL-52 De-Escalator"; code = "KLIJL"; }
    { layer = "fn3"; key = "F"; name = "EAT-700 Expendable Napalm"; code = "KKJIJ"; }
    { layer = "fn3"; key = "V"; name = "EAT-411 Leveller"; code = "KKJIK"; }
    { layer = "fn3"; key = "4"; name = "40-K Meltagun"; code = "KJIJJK"; }
    { layer = "fn3"; key = "T"; name = "B/MD C4 Pack"; code = "KLIILI"; }
    { layer = "fn3"; key = "2"; name = "GL-28 Belt-Fed Grenade Launcher"; code = "KJIJII"; }
    { layer = "fn3"; key = "Z"; name = "RS-422 Railgun"; code = "KLKIJL"; }
    { layer = "fn3"; key = "1"; name = "GL-21 Grenade Launcher"; code = "KJIJK"; }
    # Fn4: Support weapons, small arms/utility
    { layer = "fn4"; key = "G"; name = "MG-43 Machine Gun"; code = "KJKIL"; }
    { layer = "fn4"; key = "S"; name = "M-105 Stalwart"; code = "KJKIIJ"; }
    { layer = "fn4"; key = "F"; name = "FLAM-40 Flamethrower"; code = "KJIKI"; }
    { layer = "fn4"; key = "Z"; name = "LAS-98 Laser Cannon"; code = "KJKIJ"; }
    { layer = "fn4"; key = "C"; name = "ARC-3 Arc Thrower"; code = "KLKIJJ"; }
    { layer = "fn4"; key = "W"; name = "MG-206 Heavy Machine Gun"; code = "KJIKK"; }
    { layer = "fn4"; key = "B"; name = "CQC-20 Breaching Hammer"; code = "KJLJI"; }
    { layer = "fn4"; key = "E"; name = "PLAS-45 Epoch"; code = "KJIJL"; }
    { layer = "fn4"; key = "4"; name = "MGX-42 Bullet Storm"; code = "KJKLIJ"; }
    { layer = "fn4"; key = "D"; name = "CQC-9 Defoliation Tool"; code = "KJLLK"; }
    { layer = "fn4"; key = "T"; name = "TX-41 Sterilizer"; code = "KJIKJ"; }
    { layer = "fn4"; key = "1"; name = "MS-11 Solo Silo"; code = "KILKK"; }
    { layer = "fn4"; key = "V"; name = "B/FLAM-80 Cremator"; code = "KKLKII"; }
    { layer = "fn4"; key = "Q"; name = "M-1000 Maxigun"; code = "KJLKII"; }
    { layer = "fn4"; key = "R"; name = "CQC-1 One True Flag"; code = "KJLLI"; }
    # Fn5: Backpacks + Emplacements
    { layer = "fn5"; key = "S"; name = "B-1 Supply Pack"; code = "KJKIIK"; }
    { layer = "fn5"; key = "W"; name = "LIFT-850 Jump Pack"; code = "KIIKI"; }
    { layer = "fn5"; key = "B"; name = "SH-20 Ballistic Shield Backpack"; code = "KJKKIJ"; }
    { layer = "fn5"; key = "G"; name = ''"Guard Dog"''; code = "KIJILK"; }
    { layer = "fn5"; key = "R"; name = ''"Guard Dog" Rover''; code = "KIJILL"; }
    { layer = "fn5"; key = "D"; name = "Shield Generator Pack"; code = "KIJLJL"; }
    { layer = "fn5"; key = "V"; name = "Directional Shield"; code = "KIJLII"; }
    { layer = "fn5"; key = "F"; name = "Hot Dog"; code = "KIJIJJ"; }
    { layer = "fn5"; key = "E"; name = "Portable Hellbomb"; code = "KLIII"; }
    { layer = "fn5"; key = "C"; name = "K-9"; code = "KIJILJ"; }
    { layer = "fn5"; key = "Q"; name = "Hover Pack"; code = "KIIKJL"; }
    { layer = "fn5"; key = "T"; name = "Dog Breath"; code = "KIJILI"; }
    { layer = "fn5"; key = "X"; name = "Warp Pack"; code = "KJLKJL"; }
    { layer = "fn5"; key = "A"; name = "Anti-Personnel Minefield"; code = "KJIL"; }
    { layer = "fn5"; key = "4"; name = "Incendiary Mines"; code = "KJJK"; }
    { layer = "fn5"; key = "1"; name = "Anti-Tank Mines"; code = "KJII"; }
    { layer = "fn5"; key = "Z"; name = "Gas Mines"; code = "KJJL"; }
    { layer = "fn5"; key = "2"; name = "Shield Generator Relay"; code = "KIJLJK"; }
    { layer = "fn5"; key = "5"; name = "E/MG-101 HMG Emplacement"; code = "KIJLLJ"; }
    { layer = "fn5"; key = "3"; name = "E/GL-21 Grenadier Battlement"; code = "KLKJL"; }
    { layer = "fn5"; key = "6"; name = "E/AT-12 Anti-Tank Emplacement"; code = "KIJLLL"; }
  ];

  # The thumb cluster only has 4 keys, all already spoken for (Fn, Mod,
  # Space, Fn2) -- there's no physical key left to hold for Fn3/Fn4/Fn5.
  # UHK layers nest: a key ON the Fn layer can itself hold-switch into
  # another layer. The second key comes from the leftmost column (outside
  # the WASD block) so index/middle/ring stay on WASD while reaching it.
  layerAccess = [
    { layer = "fn"; index = 13; target = "fn3"; } # key left of A (Ctrl on base, unused on Fn)
    { layer = "fn"; index = 7; target = "fn4"; } # Tab
    { layer = "fn"; index = 26; target = "fn5"; } # key left of Z (2nd Ctrl on base, unused on Fn)
  ];

  module1Len = lib.length (findModule (findLayer qwr "fn") 1).keyActions;

  initialLayerModule1 = {
    fn = (findModule (findLayer qwr "fn") 1).keyActions;
    fn2 = (findModule (findLayer qwr "fn2") 1).keyActions;
    fn3 = noneActions module1Len;
    fn4 = noneActions module1Len;
    fn5 = noneActions module1Len;
  };

  setKeyAction = list: index: action: lib.imap0 (i: a: if i == index then action else a) list;

  stratagemFold = lib.foldl'
    (acc: s:
      let
        macroIndex = acc.macroCount;
      in
      acc // {
        layerModule1 = acc.layerModule1 // {
          ${s.layer} = setKeyAction acc.layerModule1.${s.layer} keyIndex.${s.key} {
            keyActionType = "playMacro";
            inherit macroIndex;
            macroArguments = [ ];
          };
        };
        macros = acc.macros ++ [ (mkDirectionMacro s.name s.code) ];
        macroCount = acc.macroCount + 1;
      })
    { layerModule1 = initialLayerModule1; macros = [ ]; macroCount = lib.length baseConfig.macros; }
    stratagems;

  withAccess = lib.foldl'
    (acc: a: acc // {
      layerModule1 = acc.layerModule1 // {
        ${a.layer} = setKeyAction acc.layerModule1.${a.layer} a.index {
          keyActionType = "switchLayer";
          layer = a.target;
          switchLayerMode = "hold";
        };
      };
    })
    stratagemFold
    layerAccess;

  # base/mod/mouse untouched (normal typing and movement keep working);
  # fn/fn2 get their existing module 1 replaced with the built bindings;
  # fn3/fn4/fn5 are brand new layers, same module shape as fn's but
  # starting from "none" everywhere except what stratagems placed.
  hd2ExistingLayers = map
    (l:
      if withAccess.layerModule1 ? ${l.id} then
        l // {
          modules = map
            (m: if m.id == 1 then m // { keyActions = withAccess.layerModule1.${l.id}; } else m)
            l.modules;
        }
      else l)
    qwr.layers;

  hd2NewLayers = map
    (layerId: {
      id = layerId;
      modules = map
        (m:
          if m.id == 1
          then { id = 1; keyActions = withAccess.layerModule1.${layerId}; }
          else { id = m.id; keyActions = noneActions (lib.length m.keyActions); })
        (findLayer qwr "fn").modules;
    })
    [ "fn3" "fn4" "fn5" ];

  hd2Keymap = qwr // {
    abbreviation = "HD2";
    name = "Helldivers 2";
    isDefault = false;
    layers = hd2ExistingLayers ++ hd2NewLayers;
  };

  # Macro name -> sops placeholder, substituted into the base macro's
  # first text action. Positions in baseConfig.macros are left alone (other
  # keymaps' playMacro bindings reference them by array index), only the
  # text content changes.
  secretMacroPlaceholders = {
    "Type old email" = config.sops.placeholder."uhk-keymaps/old_email";
    "Type personal email" = config.sops.placeholder."uhk-keymaps/personal_email";
    "Write work email" = config.sops.placeholder."uhk-keymaps/work_email";
  };

  patchedBaseMacros = map
    (m:
      if secretMacroPlaceholders ? ${m.name}
      then m // {
        macroActions = setKeyAction m.macroActions 0
          ((lib.elemAt m.macroActions 0) // { text = secretMacroPlaceholders.${m.name}; });
      }
      else m)
    baseConfig.macros;

  finalConfig = baseConfig // {
    keymaps = baseConfig.keymaps ++ [ hd2Keymap ];
    macros = patchedBaseMacros ++ withAccess.macros;
  };

  secretsFile = ../../../../secrets/ali-desktop/uhk-keymaps.yaml;
in
{
  options.programs.uhkKeymaps = {
    enable = lib.mkEnableOption "declarative UHK keymap generation";
  };

  config = lib.mkIf cfg.enable {
    sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    sops.secrets = {
      "uhk-keymaps/old_email" = { sopsFile = secretsFile; key = "old_email"; };
      "uhk-keymaps/personal_email" = { sopsFile = secretsFile; key = "personal_email"; };
      "uhk-keymaps/work_email" = { sopsFile = secretsFile; key = "work_email"; };
    };

    # Never xdg.configFile -- that symlinks into the world-readable Nix
    # store, which would put the decrypted email addresses right back
    # into the store the sops.secrets above exist to keep them out of.
    # sops.templates substitutes the placeholders at activation time and
    # writes only the finished file to a runtime-only path.
    sops.templates."uhk-user-config.json".content = builtins.toJSON finalConfig;
  };
}
