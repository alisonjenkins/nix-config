# Manual fix-ups around the auto-generated arkana-mods.nix. Three lists:
#
#   replacements — newer file-IDs for mods that either weren't resolvable
#                  via cfwidget pagination or whose Arkana version doesn't
#                  match our bumped Create 6.0.10. The original arkana
#                  entry is filtered out by (projectID, fileID) match.
#                  Each replacement may set `alwaysInclude = true` when the
#                  mod is part of the Aeronautics floor (Create itself is
#                  the only such case today); otherwise the replacement
#                  rides along with its `origProjectID`'s group enable.
#
#   skipped      — dead mods (no live file on CurseForge). Always dropped
#                  from the server tree; client manifest also strips them
#                  so the CurseForge launcher doesn't fail import.
#
#   disabled     — mods that boot-fail even when their group is enabled.
#                  Bisection populates this. Same shape as `skipped` but
#                  semantically distinct (mod still exists upstream, we
#                  just can't run it). Empty until the floor smoke test
#                  surfaces something.
#
# When regenerating arkana-mods.nix for a future Arkana bump, re-check
# replacements — most cfwidget pagination misses will resolve normally
# against a newer manifest.
{ fetchurl }:
{
  replacements = [
    {
      # Arkana 1.5 references fileID 6168249 which is gated off
      # cfwidget's pagination. Bump to the newest 1.21.1/NeoForge release
      # that is still on the recent list — minor API drift only.
      origProjectID = 1001614;
      origFileID    = 6168249;
      projectID     = 1001614;
      fileID        = 7941057;
      required      = true;
      filename      = "lionfishapi-2.7-fix-fix.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7941/57/lionfishapi-2.7-fix-fix.jar";
        name   = "lionfishapi-2.7-fix-fix.jar";
        sha256 = "1j3rccsq02ix1y4vl07nsiwhh7p24zi4srqippbhgmzpq47wj08b";
      };
    }
    {
      # Texture pack — API-stable across versions, safe to bump.
      origProjectID = 813608;
      origFileID    = 6599939;
      projectID     = 813608;
      fileID        = 8005143;
      required      = true;
      filename      = "FA+All_Extensions-v1.9.zip";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8005/143/FA%2BAll_Extensions-v1.9.zip";
        name   = "FA+All_Extensions-v1.9.zip";
        sha256 = "1r73nb3dcr3afb04sfbpi1hdiwddirnqdcnvfgvpil5bhjfa3ir0";
      };
    }
    {
      # create_factory_logistics 1.4.7 ships a mixin into Create's
      # GenericPackagerBlockEntity that misses on Create 6.0.10 (signature
      # changed). 1.4.9 is the post-6.0.9 release that targets the new
      # signature. Bumping fixes the cascading Create mod-construction
      # crash too.
      origProjectID = 1218807;
      origFileID    = 6925758;
      projectID     = 1218807;
      fileID        = 7469951;
      required      = true;
      filename      = "create_factory_logistics-1.21.1-1.4.9.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7469/951/create_factory_logistics-1.21.1-1.4.9.jar";
        name   = "create_factory_logistics-1.21.1-1.4.9.jar";
        sha256 = "1sa5i2zk470blgkdv7k8xbl49ld8p7h7qrrpsv3zyvv6ps421lqd";
      };
    }
    {
      # 2.0.1 calls `TagGen.tagBlockAndItem(String[])` which Create 6.0.10
      # removed. 2.0.2 (released against 6.0.8 but compatible with 6.0.10)
      # uses the new tag-gen API.
      origProjectID = 1005676;
      origFileID    = 6829058;
      projectID     = 1005676;
      fileID        = 7192082;
      required      = true;
      filename      = "create_aquatic_ambitions-1.21.1-2.0.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7192/82/create_aquatic_ambitions-1.21.1-2.0.2.jar";
        name   = "create_aquatic_ambitions-1.21.1-2.0.2.jar";
        sha256 = "1354gh585nq12a20869s2f5gprw2zb835zff6xy6j328mh7nnarh";
      };
    }
    # NOTE: tried Apotheosis 8.4 → 8.5.2, Apoth* family bumps, and
    # farm_and_charm 1.1.3 → 1.1.22 to clear the registry-init NPEs that
    # surface once Aeronautics + Create 6.0.10 are layered on Arkana.
    # Both bumps cascaded badly: candlelight 2.1.0 + bakery require the
    # old farm_and_charm 1.1.3 API; Apotheosis 8.5.2 still hits the same
    # sigil_of_withdrawal NPE; new failures appeared on irons_jewelry,
    # waystones, forbidden_arcanus. Net-negative — reverted. The Arkana
    # modpack is internally tuned for Create 6.0.6 / NeoForge 21.1.206 and
    # the cross-addon API surface is fragile under bumps. See the
    # "Known limitation" note in default.nix.
    {
      # Create itself — required by every overlay mod (Aeronautics, Sable,
      # Big Cannons, New Age, Offroad, Simulated). Arkana ships 6.0.6 but
      # Aeronautics 1.2.1 floor is 6.0.10. Marked `alwaysInclude` so 6.0.10
      # is in mods/ even when no Arkana group is enabled — Create is part
      # of the Aeronautics floor, not Arkana content.
      alwaysInclude = true;
      origProjectID = 328085;
      origFileID    = 6641610;
      projectID     = 328085;
      fileID        = 7963363;
      required      = true;
      filename      = "create-1.21.1-6.0.10.jar";
      jar = fetchurl {
        url    = "https://cdn.modrinth.com/data/LNytGWDc/versions/UjX6dr61/create-1.21.1-6.0.10.jar";
        name   = "create-1.21.1-6.0.10.jar";
        sha256 = "0yp3xyg7ary122zximlg2yg6dd5gnljjj2mjiddizfpi15bzx1zg";
      };
    }
  ];

  # Discontinued mods with no live file on CurseForge. Server ignores them;
  # client derivation strips matching entries from manifest.json so the
  # CurseForge launcher doesn't fail import.
  skipped = [
    {
      projectID = 1171410;
      fileID    = 6161857;
      reason    = "Ender's Nameless Necromancy is discontinued; CurseForge has no published files";
    }
  ];

  # Mods that boot-fail under our bumped Create + NeoForge even when their
  # group is enabled. Populated by the bisect workflow as offenders surface.
  # Set `fileID = null` to disable every version of a project; otherwise
  # disable only the specific (projectID, fileID) pair (lets a future
  # version replacement re-enable the mod).
  #
  # Format:  { projectID = N; fileID = M | null; reason = "<crash>"; phase = "<phase>"; }
  disabled = [ ];
}
