# Pinned EmuDeck checkout — single source of truth for the rev/hash.
#
# Shared by:
#   - modules/emulation/controls-emudeck.nix  (ships the curated control configs)
#   - flake-modules/emulation-checks.nix       (bitrot guard: asserts the
#                                               referenced config paths still
#                                               exist at this rev via nix flake check)
#
# Bump deliberately: change rev + sha256 here, then re-verify the configs/<id>
# paths in controls-emudeck.nix (and run `nix flake check`). Keeping the pin in
# one place means the check always validates the SAME rev the configs use.
{
  owner = "dragoonDorise";
  repo = "EmuDeck";
  rev = "125a09a37f49c013338a9bb2811505b18844c988";
  sha256 = "0rgsw8af00d4xawi3kgh2n0r5mkzv1yd0p4gpd7lqm63gddihia9";
}
