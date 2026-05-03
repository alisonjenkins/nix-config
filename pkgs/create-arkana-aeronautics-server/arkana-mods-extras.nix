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
      # Arkana 1.5 references fileID 6168249 which cfwidget can't resolve
      # (older than its pagination window). The fileID IS still live on
      # mediafilez — we just had to discover the filename by guessing.
      # Originally bumped to 2.7-fix-fix but that release dropped the
      # `com.github.L_Ender.lionfishapi.server.animation.IAnimatedEntity`
      # class which L_Ender's Cataclysm + irons_spellbooks +
      # cataclysm_spellbooks all hard-link to. 2.6 keeps the class.
      origProjectID = 1001614;
      origFileID    = 6168249;
      projectID     = 1001614;
      fileID        = 6168249;
      required      = true;
      filename      = "lionfishapi-2.6.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/6168/249/lionfishapi-2.6.jar";
        name   = "lionfishapi-2.6.jar";
        sha256 = "0pq222nwm31prvj0y7rgx36hqanqb77rpp8klnhbnlc31vqbfmky";
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
  disabled = [
    {
      projectID = 1111063;
      fileID    = null;
      reason    = "takesapillage requires resourcefullib >=3.0.12; Arkana ships 3.0.11 and bumping resourcefullib has wide blast radius (40+ dependents). Skip until Arkana refreshes.";
      phase     = "dependency-resolution";
    }
    # ---- registry-init NPEs surfaced by all-groups bisect ----
    # farm_and_charm 1.1.3 ships an ItemStack.getRarity mixin that
    # resolves `farm_and_charm:chicken_coop` via DeferredHolder during
    # other mods' RegisterEvent — under our bumped Create 6.0.10 the
    # registration order shifts and the holder unbinds. Bumping to 1.1.22
    # cascades into candlelight + bakery API breakage (tried earlier).
    # Drop farm_and_charm and its three Let's Do consumers.
    { projectID = 1038103; fileID = null; reason = "farm_and_charm 1.1.3 mixin DeferredHolder NPE on chicken_coop under Create 6.0.10."; phase = "registry-init"; }
    { projectID = 1038130; fileID = null; reason = "bakery hard-deps farm_and_charm (disabled)."; phase = "dependency-resolution"; }
    { projectID = 1038106; fileID = null; reason = "brewery hard-deps farm_and_charm (disabled)."; phase = "dependency-resolution"; }
    { projectID = 1038117; fileID = null; reason = "candlelight hard-deps farm_and_charm (disabled)."; phase = "dependency-resolution"; }
    # Apotheosis 8.4.0's WithdrawalRecipe.<init> resolves
    # `apotheosis:sigil_of_withdrawal` from a DeferredHolder during item
    # RegisterEvent — items haven't all registered yet → unbound holder
    # NPE. 8.5.2 doesn't fix it; bumping 8.5.2 cascades into Let's Do
    # candlelight + bakery API breakage (verified earlier).
    { projectID = 313970;  fileID = null; reason = "Apotheosis 8.4.0 sigil_of_withdrawal DeferredHolder NPE; 8.5.2 bump cascades into other mods' API breakage."; phase = "registry-init"; }
    { projectID = 985468;  fileID = null; reason = "ancientreforging hard-deps apotheosis (disabled)."; phase = "dependency-resolution"; }
    { projectID = 986982;  fileID = null; reason = "apothiccombat hard-deps apotheosis (disabled)."; phase = "dependency-resolution"; }
    { projectID = 1244863; fileID = null; reason = "irons_apothic hard-deps apotheosis (disabled)."; phase = "dependency-resolution"; }
    # GlitchCore 2.1.0.0 hits `NullPointerException: at index 0` deep in
    # `RegistryHelper.lambda$accept$0` during a RegisterEvent —
    # ImmutableList.construct rejecting a null. Upstream bug; no newer
    # GlitchCore for 1.21.1.
    { projectID = 955399;  fileID = null; reason = "GlitchCore 2.1.0.0 NPE in RegistryHelper.accept (ImmutableList.construct null at index 0)."; phase = "registry-init"; }
    { projectID = 220318;  fileID = null; reason = "BiomesOPlenty hard-deps glitchcore (disabled)."; phase = "dependency-resolution"; }
    # JER Integration calls `config.get(...)` from FMLCommonSetupEvent
    # which fires before NeoForge has loaded mod configs — IllegalState.
    # Likely an upstream incompatibility with NeoForge 21.1.x; older
    # Forge ran setup events in a different order.
    { projectID = 506948;  fileID = null; reason = "jerintegration calls config.get from FMLCommonSetupEvent before config loaded; NeoForge 21.1.x lifecycle incompatibility."; phase = "common-setup"; }
  ];
}
