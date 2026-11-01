let
  # USB HID usage ids of the keys a stratagem direction can be bound to.
  hidKey = { W = 26; A = 4; S = 22; D = 7; I = 12; J = 13; K = 14; L = 15; };
in
{
  # Left-half (module 1) key index for each letter/digit, confirmed
  # empirically against a real export's QWR base layer scancodes.
  keyIndex = {
    "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6;
    Q = 8; W = 9; E = 10; R = 11; T = 12;
    A = 14; S = 15; D = 16; F = 17; G = 18;
    Z = 21; X = 22; C = 23; V = 24; B = 25;
  };

  # Key the game expects for each direction in stratagems.nix codes. Rebinding
  # the game's stratagem keys means editing only this attrset.
  directionKey = { U = hidKey.W; L = hidKey.A; D = hidKey.S; R = hidKey.D; };
  leftCtrlMask = 1;
  holdMs = 100;
  gapMs = 100;
}
