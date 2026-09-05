{ lib, helpers, mkDirectionMacro, baseConfig }:
let
  inherit (import ./stratagems.nix) stratagems layerAccess;
  inherit (import ./constants.nix) keyIndex;
  inherit (helpers) findLayer findModule noneActions setKeyAction;

  qwr = lib.findFirst (k: k.abbreviation == "QWR") (throw "QWR keymap not found in base-user-config.json") baseConfig.keymaps;

  module1Len = lib.length (findModule (findLayer qwr "fn") 1).keyActions;

  initialLayerModule1 = {
    fn = (findModule (findLayer qwr "fn") 1).keyActions;
    fn2 = (findModule (findLayer qwr "fn2") 1).keyActions;
    fn3 = noneActions module1Len;
    fn4 = noneActions module1Len;
    fn5 = noneActions module1Len;
  };

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
in
{
  keymap = qwr // {
    abbreviation = "HD2";
    name = "Helldivers 2";
    isDefault = false;
    layers = hd2ExistingLayers ++ hd2NewLayers;
  };
  macros = withAccess.macros;
}
