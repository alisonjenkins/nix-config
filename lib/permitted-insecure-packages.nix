# Insecure packages this flake accepts, by exact name-version so each
# exception lapses on the next bump. One list for every pkgs instance:
# the NixOS module (modules/desktop-base) and the standalone home-manager
# pkgs (flake-modules/hosts/home-only). Each entry needs a
# pins/registry.json record.
[
  # EOL vendored Electron 39.2.7; see pins/registry.json
  # keybase-gui-6.6.3-insecure.
  "keybase-gui-6.6.3"
]
