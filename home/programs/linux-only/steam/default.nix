{ pkgs, lib, config, ... }:

let
  # Patched bubblewrap built statically to work inside Steam's FHS environment
  patchedBwrap = pkgs.pkgsStatic.bubblewrap.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      ../../../../patches/bubblewrap-allow-caps.patch
    ];
  });
in
{
  # Set BWRAP environment variable to point pressure-vessel to our patched bwrap
  # This avoids modifying Steam's files which get verified and replaced on each launch
  home.sessionVariables = {
    BWRAP = "${patchedBwrap}/bin/bwrap";
  };
}
