let
  meta = import ./meta.nix;
  macros = import ./macros.nix;
  keymaps = [
    (import ./keymaps/colemak-mac.nix) # COM
    (import ./keymaps/colemak-pc.nix) # COL
    (import ./keymaps/dvorak-mac.nix) # DVM
    (import ./keymaps/dvorak-pc.nix) # DVO
    (import ./keymaps/empty.nix) # EMP
    (import ./keymaps/qwerty-mac.nix) # QWM
    (import ./keymaps/qwerty-pc.nix) # QWR
  ];
in
meta // { inherit keymaps macros; }
