# Datapacks bundled into the server tree. Server-side only — datapacks
# don't ship in the client zip (they're applied to the world during
# server-side world-load and synced to clients automatically).
#
# Each entry is just a fetchurl-produced zip; the server's entrypoint
# copies these into /data/world/datapacks/ on every boot (idempotent
# overwrite — picks up version bumps without manual PVC fiddling).
{ fetchurl }:
[
  {
    # Patches [Let's Do] Herbal Brews vanilla-flower loot tables so
    # broken vanilla flowers only drop Tea Blossoms when sheared (not
    # when Fortune'd / luck-rolled). Without this, Herbal Brews
    # double-dips with mods that alter vanilla flower drops and
    # produces Tea Blossoms incorrectly. Datapack is MIT-licensed
    # (onjulraz / satisfyu).
    filename = "lets-do-herbal-brews-tea-blossoms-from-shears-only-1.0.0.zip";
    zip = fetchurl {
      url    = "https://cdn.modrinth.com/data/fyquDQQA/versions/C753E9nv/%5BLet%27s%20Do%5D%20Herbal%20Brews%20Tea%20Blossom%20from%20Shears%20Only.zip";
      name   = "lets-do-herbal-brews-tea-blossoms-from-shears-only-1.0.0.zip";
      sha256 = "0bhiaadmw0fqga2gg49h9vw9i1vnifx9ncpc0kn3yibfqx3phzz0";
    };
  }
]
