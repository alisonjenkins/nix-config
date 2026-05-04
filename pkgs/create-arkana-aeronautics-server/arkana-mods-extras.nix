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
    {

      alwaysInclude = true;
      origProjectID = 508933;
      origFileID    = 6791190;
      projectID     = 508933;
      fileID        = 7977110;
      required      = true;
      filename      = "DistantHorizons-3.0.2-b-1.21.1-fabric-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7977/110/DistantHorizons-3.0.2-b-1.21.1-fabric-neoforge.jar";
        name   = "DistantHorizons-3.0.2-b-1.21.1-fabric-neoforge.jar";
        sha256 = "0mgq2s7kap2y8zqrn4fhhn1imfpmsr4hlsrhxgqxrvjdmhaxms7z";
      };
    }
    {
      # 1.7.0's PotionMixingRecipesMixin invokes
      # com.simibubi.create.foundation.fluid.FluidIngredient::fromFluidStack
      # which Create 6.0.10 removed/relocated. JEI's loadCategories class-loads
      # every Create mixin target during recipe registration, so the missing
      # class crashes the client at world join (server has no JEI, never hit
      # this path). 1.10.0 is explicitly built for Create 6.0.10 (CurseForge
      # display name: "Create: Dragons Plus 1.10.0 for Create 1.21.1-6.0.10").
      origProjectID = 1216624;
      origFileID    = 6946959;
      projectID     = 1216624;
      fileID        = 7966760;
      required      = true;
      filename      = "CreateDragonsPlus-1.10.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7966/760/CreateDragonsPlus-1.10.0.jar";
        name   = "CreateDragonsPlus-1.10.0.jar";
        sha256 = "0bv12ba89wll4dd6j2p947ryhrqpp68dabyxs99xin8y4p83y577";
      };
    }
    {
      # Patch bump 21.1.10 → 21.1.11 (semver-compatible, Bookshelf-style lib).
      origProjectID = 1023259;
      origFileID    = 6910558;
      projectID     = 1023259;
      fileID        = 6961457;
      required      = true;
      filename      = "prickle-neoforge-1.21.1-21.1.11.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/6961/457/prickle-neoforge-1.21.1-21.1.11.jar";
        name   = "prickle-neoforge-1.21.1-21.1.11.jar";
        sha256 = "0rxi9rhz8y6dz9frhq43v16yqa88ar00jvq5mm0zxiyk5r26rx6c";
      };
    }
    {
      # Patch bump 21.1.2 → 21.1.3.
      origProjectID = 280510;
      origFileID    = 5824104;
      projectID     = 280510;
      fileID        = 7115922;
      required      = true;
      filename      = "attributefix-neoforge-1.21.1-21.1.3.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7115/922/attributefix-neoforge-1.21.1-21.1.3.jar";
        name   = "attributefix-neoforge-1.21.1-21.1.3.jar";
        sha256 = "1m1a70n7vhx576rl00253h744g9jsgsf6kf1hh90f9788hyhzcmj";
      };
    }
    {
      # Bookshelf 21.1.68 → 21.1.81. Lib used by Apothic family + many
      # Arkana mods; minor bumps within 21.1.x are API-compatible per
      # blamejared's semver discipline.
      origProjectID = 228525;
      origFileID    = 6909578;
      projectID     = 228525;
      fileID        = 7606240;
      required      = true;
      filename      = "bookshelf-neoforge-1.21.1-21.1.81.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7606/240/bookshelf-neoforge-1.21.1-21.1.81.jar";
        name   = "bookshelf-neoforge-1.21.1-21.1.81.jar";
        sha256 = "0xiyid4k8y6b7yjaiw4x6yjncvnrd6s7z3w05d612sibv908vs0r";
      };
    }
    {
      # Patch bump 1.0.33 → 1.0.35 (henkelmax gravestone).
      origProjectID = 238551;
      origFileID    = 6930851;
      projectID     = 238551;
      fileID        = 7099728;
      required      = true;
      filename      = "gravestone-neoforge-1.21.1-1.0.35.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7099/728/gravestone-neoforge-1.21.1-1.0.35.jar";
        name   = "gravestone-neoforge-1.21.1-1.0.35.jar";
        sha256 = "1c05866nhpb6pq47n3hzyk7cdxnkb73hlsphvk2j9mg1v8ic4rba";
      };
    }
    {
      # Aether 1.5.9 → 1.5.10. Required to match deep_aether 1.1.5.1 below
      # (aether is a hard dep). Both gated to enabled `world` group via
      # arkana-mods filter.
      origProjectID = 255308;
      origFileID    = 6894706;
      projectID     = 255308;
      fileID        = 7043502;
      required      = true;
      filename      = "aether-1.21.1-1.5.10-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7043/502/aether-1.21.1-1.5.10-neoforge.jar";
        name   = "aether-1.21.1-1.5.10-neoforge.jar";
        sha256 = "1gqdcg4f9jz7c45yy381jc7jg7lrb5xhlyg9b2j1g8302lq8d4xi";
      };
    }
    {
      # Deep Aether 1.1.4 → 1.1.5.1.
      origProjectID = 852465;
      origFileID    = 6839619;
      projectID     = 852465;
      fileID        = 7843283;
      required      = true;
      filename      = "deep_aether-1.21.1-1.1.5.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7843/283/deep_aether-1.21.1-1.1.5.1.jar";
        name   = "deep_aether-1.21.1-1.1.5.1.jar";
        sha256 = "1r8cps5x08c9nv02dm7z4nxdym3kbb1v51g78hrr7fqm0ybssm8g";
      };
    }
    # ---- Ars Nouveau family ----
    # Bumping the family together because the addons declare hard
    # version-range deps on ars_nouveau and on each other; mismatched
    # versions break client model loading and crash addons that hook
    # ars_nouveau spell registration.
    {
      origProjectID = 401955;
      origFileID    = 6954892;
      projectID     = 401955;
      fileID        = 7764018;
      required      = true;
      filename      = "ars_nouveau-1.21.1-5.11.3.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7764/018/ars_nouveau-1.21.1-5.11.3.jar";
        name   = "ars_nouveau-1.21.1-5.11.3.jar";
        sha256 = "0dxvvxa03fznyv5ixl4sml1wwmnwy2yqx0f6sq2f5sspd5ay3xci";
      };
    }
    {
      origProjectID = 974408;
      origFileID    = 6928685;
      projectID     = 974408;
      fileID        = 7646325;
      required      = true;
      filename      = "ars_additions-1.21.1-21.3.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7646/325/ars_additions-1.21.1-21.3.0.jar";
        name   = "ars_additions-1.21.1-21.3.0.jar";
        sha256 = "16rc6qgr1hhpbz3vdgq2h9ysvfy9lxs1kklcc03q1lwwqgqa6d76";
      };
    }
    {
      origProjectID = 1061812;
      origFileID    = 6917586;
      projectID     = 1061812;
      fileID        = 7534518;
      required      = true;
      filename      = "ars_controle-1.21.1-1.6.15.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7534/518/ars_controle-1.21.1-1.6.15.jar";
        name   = "ars_controle-1.21.1-1.6.15.jar";
        sha256 = "0l88y7qiy6a3asys6h4dbdaxjy3hiw41wrj6a51vwmyswijw9wl6";
      };
    }
    {
      origProjectID = 575698;
      origFileID    = 6279953;
      projectID     = 575698;
      fileID        = 7528185;
      required      = true;
      filename      = "ars_creo-1.21.1-5.2.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7528/185/ars_creo-1.21.1-5.2.0.jar";
        name   = "ars_creo-1.21.1-5.2.0.jar";
        sha256 = "0bybq7r8mix0al8avwh9685sadfk6x2ikj5hwmvv264l7vf4lm34";
      };
    }
    {
      origProjectID = 1153666;
      origFileID    = 6811235;
      projectID     = 1153666;
      fileID        = 7956082;
      required      = true;
      filename      = "ars_elemancy-1.21.1-1.17.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7956/082/ars_elemancy-1.21.1-1.17.jar";
        name   = "ars_elemancy-1.21.1-1.17.jar";
        sha256 = "0x0nd4fwa21ccfh27pbvdgaq4iggpfgd9mpdfl748i0p02nzm6y0";
      };
    }
    {
      origProjectID = 561470;
      origFileID    = 6803373;
      projectID     = 561470;
      fileID        = 8005065;
      required      = true;
      filename      = "ars_elemental-1.21.1-0.7.9.3.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8005/065/ars_elemental-1.21.1-0.7.9.3.jar";
        name   = "ars_elemental-1.21.1-0.7.9.3.jar";
        sha256 = "1lnglp8ddxahi4idmlpywpfrl3caslhdhzsxdgs6ygl63lh788bj";
      };
    }
    {
      # 2.3.0 → 2.7.6. Significant feature jump but Ars Nouveau 5.11.x is
      # the matched floor; ars_technica's mods.toml requires ars_nouveau
      # >= 5.11.0 in 2.7.x.
      origProjectID = 1096161;
      origFileID    = 6825993;
      projectID     = 1096161;
      fileID        = 7642730;
      required      = true;
      filename      = "ars_technica-1.21.1-2.7.6.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7642/730/ars_technica-1.21.1-2.7.6.jar";
        name   = "ars_technica-1.21.1-2.7.6.jar";
        sha256 = "178msgaih63b2gc71rgpiqfa3a4lci5biqk95hk3ijn8z0whzdv4";
      };
    }
    # NOTE: reliquified_ars_nouveau NOT bumped — 0.7.1 requires
    # relics >=0.11.14 (major API break: IRelicItem moved, EffectRegistry
    # removed, ExperienceAddEvent gone). Bumping relics to 0.11.16 broke
    # arcane_abilities, reliquified_lenders_cataclysm, and a relics-using
    # twilightforest plugin. 0.6.1 stays — its dep range `ars_nouveau
    # >=5.10.2` accepts 5.11.3 fine.
    {
      origProjectID = 746215;
      origFileID    = 6646495;
      projectID     = 746215;
      fileID        = 7638376;
      required      = true;
      filename      = "starbunclemania-1.21.1-1.5.6.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7638/376/starbunclemania-1.21.1-1.5.6.jar";
        name   = "starbunclemania-1.21.1-1.5.6.jar";
        sha256 = "1zgd99gq4ahjgzpz17lvk77zzvpqybhnzzyzbj9zjx805fjw5yvx";
      };
    }
    {
      origProjectID = 1023517;
      origFileID    = 6784398;
      projectID     = 1023517;
      fileID        = 8015114;
      required      = true;
      filename      = "not_enough_glyphs-1.21.1-4.3.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8015/114/not_enough_glyphs-1.21.1-4.3.2.jar";
        name   = "not_enough_glyphs-1.21.1-4.3.2.jar";
        sha256 = "1z3vzgzj9y0424igz958vnbh040andakbd5mc8n3a566n91zgxkv";
      };
    }
    {
      origProjectID = 896746;
      origFileID    = 6919475;
      projectID     = 896746;
      fileID        = 7054319;
      required      = true;
      filename      = "amendments-1.21-2.0.8-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7054/319/amendments-1.21-2.0.8-neoforge.jar";
        name   = "amendments-1.21-2.0.8-neoforge.jar";
        sha256 = "05ah4xnij7apcgcqv1i3rbrg28bs426l5ikrvnfr2xblcvrb9x9k";
      };
    }
    {
      origProjectID = 898963;
      origFileID    = 6751650;
      projectID     = 898963;
      fileID        = 7445079;
      required      = true;
      filename      = "ApothicAttributes-1.21.1-2.9.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7445/79/ApothicAttributes-1.21.1-2.9.1.jar";
        name   = "ApothicAttributes-1.21.1-2.9.1.jar";
        sha256 = "10g38jic23saqjj4dlnhdi2qf22740q6w4lk296lyy6104yxfgbf";
      };
    }
    {
      origProjectID = 1063926;
      origFileID    = 6926290;
      projectID     = 1063926;
      fileID        = 7659120;
      required      = true;
      filename      = "ApothicEnchanting-1.21.1-1.5.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7659/120/ApothicEnchanting-1.21.1-1.5.2.jar";
        name   = "ApothicEnchanting-1.21.1-1.5.2.jar";
        sha256 = "17xvmdvra8zc39flr5i3ahp5mhhm9g5diydz8s8np2x7687w9wsh";
      };
    }
    {
      origProjectID = 986583;
      origFileID    = 6751589;
      projectID     = 986583;
      fileID        = 7492121;
      required      = true;
      filename      = "ApothicSpawners-1.21.1-1.3.4.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7492/121/ApothicSpawners-1.21.1-1.3.4.jar";
        name   = "ApothicSpawners-1.21.1-1.3.4.jar";
        sha256 = "059y35d2b878f1wzffdgqlgqpzjzww749y0jwzk3ln80kdnifvnz";
      };
    }
    {
      origProjectID = 531761;
      origFileID    = 6841890;
      projectID     = 531761;
      fileID        = 7420963;
      required      = true;
      filename      = "balm-neoforge-1.21.1-21.0.56.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7420/963/balm-neoforge-1.21.1-21.0.56.jar";
        name   = "balm-neoforge-1.21.1-21.0.56.jar";
        sha256 = "0bmk5w5ms0zpzk7ya6ngs2cc95cg0b9f59pa45mn9jyafd7dc3k7";
      };
    }
    {
      origProjectID = 242818;
      origFileID    = 6583751;
      projectID     = 242818;
      fileID        = 7281427;
      required      = true;
      filename      = "CodeChickenLib-1.21.1-4.6.1.526.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7281/427/CodeChickenLib-1.21.1-4.6.1.526.jar";
        name   = "CodeChickenLib-1.21.1-4.6.1.526.jar";
        sha256 = "015wsr26snrxbj7c6vdh2zsys8kd89a2893iw7hqgsrs7v5b0p73";
      };
    }
    {
      origProjectID = 457570;
      origFileID    = 5873783;
      projectID     = 457570;
      fileID        = 7276577;
      required      = true;
      filename      = "configured-neoforge-1.21.1-2.6.3.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7276/577/configured-neoforge-1.21.1-2.6.3.jar";
        name   = "configured-neoforge-1.21.1-2.6.3.jar";
        sha256 = "059a51wsbq15v95mnkgq7y7x59xq3ifyplc4naypqj5m0hkgs7s2";
      };
    }
    {
      origProjectID = 491794;
      origFileID    = 5756947;
      projectID     = 491794;
      fileID        = 7892943;
      required      = true;
      filename      = "ExplorersCompass-1.21.1-3.4.0-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7892/943/ExplorersCompass-1.21.1-3.4.0-neoforge.jar";
        name   = "ExplorersCompass-1.21.1-3.4.0-neoforge.jar";
        sha256 = "095g3xnlwn3xacb84xv9x0jy5hkgfdv55zh6gh6j374cv1xv9rvi";
      };
    }
    {
      origProjectID = 363363;
      origFileID    = 6875184;
      projectID     = 363363;
      fileID        = 7895926;
      required      = true;
      filename      = "ExtremeSoundMuffler-3.56_NeoForge-1.21.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7895/926/ExtremeSoundMuffler-3.56_NeoForge-1.21.jar";
        name   = "ExtremeSoundMuffler-3.56_NeoForge-1.21.jar";
        sha256 = "0cfmn9da0c3y7dnwlkflp8mrirlczahy3hr5zvlcrqs02m354h9w";
      };
    }
    {
      origProjectID = 475117;
      origFileID    = 6751538;
      projectID     = 475117;
      fileID        = 7527945;
      required      = true;
      filename      = "FastSuite-1.21.1-6.0.7.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7527/945/FastSuite-1.21.1-6.0.7.jar";
        name   = "FastSuite-1.21.1-6.0.7.jar";
        sha256 = "03f7wqflghcv42j72hlfwdpwh1jkqkqi6hjiwbwdy9yw3g84q9ry";
      };
    }
    {
      origProjectID = 429235;
      origFileID    = 5850121;
      projectID     = 429235;
      fileID        = 7524151;
      required      = true;
      filename      = "ferritecore-7.0.3-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7524/151/ferritecore-7.0.3-neoforge.jar";
        name   = "ferritecore-7.0.3-neoforge.jar";
        sha256 = "1a1hs2b22c48bpgj3h0vaajffs5lws9x90labgsbypkica1a4znq";
      };
    }
    {
      origProjectID = 549225;
      origFileID    = 6531439;
      projectID     = 549225;
      fileID        = 7530361;
      required      = true;
      filename      = "framework-neoforge-1.21.1-0.13.11.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7530/361/framework-neoforge-1.21.1-0.13.11.jar";
        name   = "framework-neoforge-1.21.1-0.13.11.jar";
        sha256 = "1x83v85xfi9g58x4lf6r4nsxvcfpwiwhkriy8v0jaz1d2q5ak7j2";
      };
    }
    {
      origProjectID = 404468;
      origFileID    = 6930910;
      projectID     = 404468;
      fileID        = 7144060;
      required      = true;
      filename      = "ftb-teams-neoforge-2101.1.5.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7144/60/ftb-teams-neoforge-2101.1.5.jar";
        name   = "ftb-teams-neoforge-2101.1.5.jar";
        sha256 = "0q2z5jr9xv1w9q3r7my4x5cm6gw0bfx73awndbk2bcv67fis0m0g";
      };
    }
    {
      origProjectID = 386134;
      origFileID    = 6930900;
      projectID     = 386134;
      fileID        = 7188395;
      required      = true;
      filename      = "ftb-ultimine-neoforge-2101.1.12.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7188/395/ftb-ultimine-neoforge-2101.1.12.jar";
        name   = "ftb-ultimine-neoforge-2101.1.12.jar";
        sha256 = "02c17f4kx6ih6iw6xir0y3szsck0ykcs0ac0jkk5p8jpf3cq138y";
      };
    }
    {
      origProjectID = 854949;
      origFileID    = 6923714;
      projectID     = 854949;
      fileID        = 7471474;
      required      = true;
      filename      = "fusion-1.2.12-neoforge-mc1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7471/474/fusion-1.2.12-neoforge-mc1.21.1.jar";
        name   = "fusion-1.2.12-neoforge-mc1.21.1.jar";
        sha256 = "033wp2sxjy08h4wzly9mm931c15wha0ryp66bch8igdphn6zfqar";
      };
    }
    {
      origProjectID = 388172;
      origFileID    = 6920810;
      projectID     = 388172;
      fileID        = 7707149;
      required      = true;
      filename      = "geckolib-neoforge-1.21.1-4.8.4.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7707/149/geckolib-neoforge-1.21.1-4.8.4.jar";
        name   = "geckolib-neoforge-1.21.1-4.8.4.jar";
        sha256 = "1jfa5gj3i7r5kij168s6jc4qxxhsnyvfsbk793ksfyk2x0jwxdm1";
      };
    }
    {
      origProjectID = 238222;
      origFileID    = 6614392;
      projectID     = 238222;
      fileID        = 7420587;
      required      = true;
      filename      = "jei-1.21.1-neoforge-19.27.0.340.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7420/587/jei-1.21.1-neoforge-19.27.0.340.jar";
        name   = "jei-1.21.1-neoforge-19.27.0.340.jar";
        sha256 = "09lqr7vvnmkgk4yhghsqz10gx4h6j5mkadmh7619bd7i69s59bwa";
      };
    }
    {
      origProjectID = 1082929;
      origFileID    = 6735758;
      projectID     = 1082929;
      fileID        = 7456313;
      required      = true;
      filename      = "lukis-crazy-chambers-1.0.3.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7456/313/lukis-crazy-chambers-1.0.3.jar";
        name   = "lukis-crazy-chambers-1.0.3.jar";
        sha256 = "0i34arvpq2iaf8zns0j5lgg94mkvb42v9jnlrq673dwwcyx9jsrz";
      };
    }
    {
      origProjectID = 1003666;
      origFileID    = 6786014;
      projectID     = 1003666;
      fileID        = 7456302;
      required      = true;
      filename      = "lukis-grand-capitals-1.1.3.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7456/302/lukis-grand-capitals-1.1.3.jar";
        name   = "lukis-grand-capitals-1.1.3.jar";
        sha256 = "0l9q7p334ahjpnzc0xdbrlzxr6lsjc6liq08wx2dkbq6sg42s62q";
      };
    }
    {
      origProjectID = 252848;
      origFileID    = 5696042;
      projectID     = 252848;
      fileID        = 7892954;
      required      = true;
      filename      = "NaturesCompass-1.21.1-3.4.0-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7892/954/NaturesCompass-1.21.1-3.4.0-neoforge.jar";
        name   = "NaturesCompass-1.21.1-3.4.0-neoforge.jar";
        sha256 = "172kjyagd7ywwmxxp75scibgllm6ilc9wryrf1anr49g3g0rl90f";
      };
    }
    {
      origProjectID = 495476;
      origFileID    = 6874068;
      projectID     = 495476;
      fileID        = 7140307;
      required      = true;
      filename      = "PuzzlesLib-v21.1.39-1.21.1-NeoForge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7140/307/PuzzlesLib-v21.1.39-1.21.1-NeoForge.jar";
        name   = "PuzzlesLib-v21.1.39-1.21.1-NeoForge.jar";
        sha256 = "05599dwhcs1p3zlfr5l4063g5g15nmjncs2ngf354nqs2y684p1h";
      };
    }
    {
      origProjectID = 412082;
      origFileID    = 6944305;
      projectID     = 412082;
      fileID        = 6949037;
      required      = true;
      filename      = "supplementaries-1.21-3.4.14-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/6949/37/supplementaries-1.21-3.4.14-neoforge.jar";
        name   = "supplementaries-1.21-3.4.14-neoforge.jar";
        sha256 = "0krwg4wjakqp6bmi67wx8p7hglbfz1nhkhx6fz2f14gjp0ph3cq4";
      };
    }
    {
      origProjectID = 254268;
      origFileID    = 5827075;
      projectID     = 254268;
      fileID        = 7197218;
      required      = true;
      filename      = "torchmaster-neoforge-1.21.1-21.1.9.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7197/218/torchmaster-neoforge-1.21.1-21.1.9.jar";
        name   = "torchmaster-neoforge-1.21.1-21.1.9.jar";
        sha256 = "01mqdrq38xazpbgg2hz4wabfbyvp2ynzy52sg9wmcxkmhnijz6nv";
      };
    }
    {
      origProjectID = 245755;
      origFileID    = 6856574;
      projectID     = 245755;
      fileID        = 7966157;
      required      = true;
      filename      = "waystones-neoforge-1.21.1-21.1.30.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7966/157/waystones-neoforge-1.21.1-21.1.30.jar";
        name   = "waystones-neoforge-1.21.1-21.1.30.jar";
        sha256 = "1dvz9alq3j8h717f2n2sjf0imckpw4nx9f8p4fy9x5zwi8yp4czk";
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
    {
      projectID = 551736;
      fileID    = 6044477;
      reason    = "sodiumdynamiclights bundles dev.lambdaurora.lambdynlights.api.* — same package as the lambdynlights_api jar another mod (sauce) consumes. JPMS rejects two providers for the same package: 'Modules sodiumdynamiclights and lambdynlights_api export package dev.lambdaurora.lambdynlights.api.item to module sauce'. Client-only visual mod; server doesn't render — drop pack-wide.";
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
    { projectID = 820977;  fileID = null; reason = "Incompatible with Create Aeronautics"; phase = "worldgen"; }
    # create_dragons_plus 1.7.0 was disabled (PotionMixingRecipesMixin
    # referenced removed Create FluidIngredient); replaced with 1.10.0
    # above (built against Create 6.0.10) instead.
    { projectID = 688768; fileID = null; reason = "Incompatible with Create Aeronautics"; phase = "worldgen"; }
  ];
}
