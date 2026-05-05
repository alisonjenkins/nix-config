# Datapacks bundled into the server tree. Server-side ships them at
# /opt/server/openloader/data/<zip>; client zip mirrors at
# overrides/openloader/data/<zip>. OpenLoader (overlay mod) auto-loads
# zips from <game-dir>/openloader/data/ into every world the server
# hosts and every world the client opens, so a single declarative list
# applies uniformly without per-world manual installation.
#
# List is currently empty — the previous Herbal Brews shears-only fix
# was removed when the user dropped the Herbal Brews mod entirely.
# Future datapacks just append new entries here.
# `fetchurl` is unused while the list is empty — keep the formal so
# future entries can fetchurl-import their zips without the caller's
# import-line changing shape.
{ fetchurl ? null }:
[
]
