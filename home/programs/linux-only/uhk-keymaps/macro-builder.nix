{ lib, constants }:
# Holds LeftCtrl, presses/holds/releases each direction with a gap between,
# then releases Ctrl -- a plain tap (press+release with no controllable
# hold) was too brief for Helldivers 2 to register reliably; this is the
# timing that actually worked on real hardware.
name: code: {
  isLooped = false;
  isPrivate = false;
  inherit name;
  macroActions =
    [
      { macroActionType = "key"; action = "press"; modifierMask = constants.leftCtrlMask; }
      { macroActionType = "delay"; delay = constants.gapMs; }
    ]
    ++ lib.concatMap
      (dir: [
        { macroActionType = "key"; action = "press"; type = "basic"; scancode = constants.scancode.${dir}; }
        { macroActionType = "delay"; delay = constants.holdMs; }
        { macroActionType = "key"; action = "release"; type = "basic"; scancode = constants.scancode.${dir}; }
        { macroActionType = "delay"; delay = constants.gapMs; }
      ])
      (lib.stringToCharacters code)
    ++ [ { macroActionType = "key"; action = "release"; modifierMask = constants.leftCtrlMask; } ];
}
