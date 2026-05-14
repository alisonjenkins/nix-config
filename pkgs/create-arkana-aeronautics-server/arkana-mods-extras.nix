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
      # Bumped by find-mod-bumps (lionfishapi).
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
    {

      alwaysInclude = true;
      origProjectID = 508933;
      origFileID    = 6791190;
      projectID     = 508933;
      fileID        = 8037637;
      required      = true;
      filename      = "DistantHorizons-3.0.3-b-1.21.1-fabric-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8037/637/DistantHorizons-3.0.3-b-1.21.1-fabric-neoforge.jar";
        name   = "DistantHorizons-3.0.3-b-1.21.1-fabric-neoforge.jar";
        sha256 = "11a7xxwf29idg45byvv78rdkspa826zgdrif9zq3brggm9z4kfns";
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
      # Bumped by find-mod-bumps (amendments).
      origProjectID = 896746;
      origFileID    = 6919475;
      projectID     = 896746;
      fileID        = 7461027;
      required      = true;
      filename      = "amendments-1.21-2.0.15-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7461/27/amendments-1.21-2.0.15-neoforge.jar";
        name   = "amendments-1.21-2.0.15-neoforge.jar";
        sha256 = "1db2ycdlnhzqgm0bq8kh2vwcn36jkq4ykld3ikp76npbqbanfkp4";
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
      # Bumped by find-mod-bumps (ftbteams).
      origProjectID = 404468;
      origFileID    = 6930910;
      projectID     = 404468;
      fileID        = 7878281;
      required      = true;
      filename      = "ftb-teams-neoforge-2101.1.10.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7878/281/ftb-teams-neoforge-2101.1.10.jar";
        name   = "ftb-teams-neoforge-2101.1.10.jar";
        sha256 = "0v3ssfkf0zl992jdmig6clgh9chfma87csdsnfm37a8i1smg4mm6";
      };
    }
    {
      # Bumped by find-mod-bumps (ftbultimine).
      origProjectID = 386134;
      origFileID    = 6930900;
      projectID     = 386134;
      fileID        = 8078515;
      required      = true;
      filename      = "ftb-ultimine-neoforge-2101.1.14.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8078/515/ftb-ultimine-neoforge-2101.1.14.jar";
        name   = "ftb-ultimine-neoforge-2101.1.14.jar";
        sha256 = "0w6966cq8aq2rcivl4bq4c8456cmckxq5h7hljbg039a36pid5nh";
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
      # Bumped by find-mod-bumps (supplementaries).
      origProjectID = 412082;
      origFileID    = 6944305;
      projectID     = 412082;
      fileID        = 8051628;
      required      = true;
      filename      = "supplementaries-neoforge-1.21.1-3.6.4.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8051/628/supplementaries-neoforge-1.21.1-3.6.4.jar";
        name   = "supplementaries-neoforge-1.21.1-3.6.4.jar";
        sha256 = "158gv3vczgnzwnsbp8p53r3wn6gkz9hm4z61iazwfp4ybwy3xdz3";
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
    # Accessories Compatibility Layer 0.1.6 had a null-holder bug where
    # Iron's Spellbooks queries Rabbit#isInvisibleTo → curio lookup →
    # AccessoriesHolderImpl.getSlotContainers() NPE because the compat
    # layer didn't auto-create holders for non-player entities. 0.1.9
    # adds the auto-create. Capped at 0.1.9 by accessories beta.49's
    # `accessories_compat_layer (,0.1.9]` dep range — newer compat
    # layers (0.1.10+) require accessories beta.53+, which we hold
    # back to avoid wider blast radius across curio-bridged mods.
    {
      origProjectID = 1315611;
      origFileID    = 6957780;
      projectID     = 1315611;
      fileID        = 7005354;
      required      = true;
      filename      = "accessories_compat_layer-neoforge-0.1.9+1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7005/354/accessories_compat_layer-neoforge-0.1.9%2B1.21.1.jar";
        name   = "accessories_compat_layer-neoforge-0.1.9+1.21.1.jar";
        sha256 = "0aq0ilfxg60sadzq3qpxhb3v0g8lkr0d97aichpp12cxj5kcsshg";
      };
    }
    {
      # EuphoriaPatcher bump 1.6.5 → 1.8.6. Arkana 1.5 ships 1.6.5; the
      # in-game updater shows "Update available: 1.8.6". Bumping silences
      # the prompt and picks up the 1.7.x and 1.8.x changelog (bug fixes
      # + new shader profile options). Tied to Complementary Shaders
      # r5.7.1; the auto-patch runs at launcher init, no manual work.
      # Marked client-only at the server-image strip layer
      # (clientOnlyProjectIDs in default.nix already contains 915902),
      # so this replacement only lands in the client zip's
      # overrides/mods. CurseForge fileID 7624100.
      origProjectID = 915902;
      origFileID    = 6653765;
      projectID     = 915902;
      fileID        = 7624100;
      required      = true;
      filename      = "EuphoriaPatcher-1.8.6-r5.7.1-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7624/100/EuphoriaPatcher-1.8.6-r5.7.1-neoforge.jar";
        name   = "EuphoriaPatcher-1.8.6-r5.7.1-neoforge.jar";
        sha256 = "1yiy46ss9zja486kvpd3wgwpr7g51hync2dy9i03mm65ndxdnqgd";
      };
    }
    {
      # ComplementaryReimagined bump r5.5.1 → r5.7.1. Arkana 1.5 ships
      # r5.5.1, but EuphoriaPatcher 1.8.6 hard-checks for r5.7.1 at
      # launcher init and refuses to patch otherwise (logs "SHADER NOT
      # FOUND: required r5.7.1, found r5.5.1"). Bumping the base shader
      # pack to r5.7.1 lets EuphoriaPatcher proceed. Shaderpack only —
      # ships as a zip in overrides/shaderpacks/, never loaded by the
      # dedicated server (project 627557 is in clientOnlyProjectIDs).
      # CurseForge fileID 7574259.
      origProjectID = 627557;
      origFileID    = 6515577;
      projectID     = 627557;
      fileID        = 7574259;
      required      = true;
      filename      = "ComplementaryReimagined_r5.7.1.zip";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7574/259/ComplementaryReimagined_r5.7.1.zip";
        name   = "ComplementaryReimagined_r5.7.1.zip";
        sha256 = "1w33kyknwc0qsi6l0saww906iwi9d3hkn0nm7hnl4bc3lws0d8i4";
      };
    }
    {
      # AllTheLeaks bump 1.0.1 → 1.1.8. Arkana 1.5 ships 1.0.1 which
      # carries a hardcoded reference to Ars Nouveau's
      # AlakarkinosConversionRegistry.LOOT_PARAMS field — that field was
      # removed/renamed in Ars Nouveau 5.10+, so 1.0.1 spams
      #   [AllTheLeaks/ERROR]: Failed to instantiate constructor.
      #   java.lang.NoSuchFieldError: ... LOOT_PARAMS
      # on every launch and the corresponding leak fix never applies.
      # 1.1.8 (released Apr 2026) has the updated registry path. Marked
      # client-only via clientOnlyProjectIDs (1091339) so server image is
      # unaffected. CurseForge fileID 7955700.
      origProjectID = 1091339;
      origFileID    = 6930692;
      projectID     = 1091339;
      fileID        = 7955700;
      required      = true;
      filename      = "alltheleaks-1.1.8+1.21.1-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7955/700/alltheleaks-1.1.8%2B1.21.1-neoforge.jar";
        name   = "alltheleaks-1.1.8+1.21.1-neoforge.jar";
        sha256 = "04b6czhnfz0kvzaaw3s525llkhc9knhhg2yn9a7irzbqm7228rhn";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1156098;
      origFileID    = 6912513;
      projectID     = 1156098;
      fileID        = 7687867;
      required      = true;
      filename      = "ConstructionSticks-1.21.1-1.3.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7687/867/ConstructionSticks-1.21.1-1.3.0.jar";
        name   = "ConstructionSticks-1.21.1-1.3.0.jar";
        sha256 = "1i8i2x76mqkgc4dfkcxdww43dhk9k8c5aqh0r89grzkqf5xy0df0";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1216624;
      origFileID    = 7966760;
      projectID     = 1216624;
      fileID        = 7970093;
      required      = true;
      filename      = "CreateDragonsPlus-1.10.0b.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7970/93/CreateDragonsPlus-1.10.0b.jar";
        name   = "CreateDragonsPlus-1.10.0b.jar";
        sha256 = "0rlx5857plkn4vwb4g3j4l4zhi3abva6gjpb4kyvx2scl1g7mi4c";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 945149;
      origFileID    = 6923054;
      projectID     = 945149;
      fileID        = 8070984;
      required      = true;
      filename      = "Glassential-renewed-1.21.1-3.4.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8070/984/Glassential-renewed-1.21.1-3.4.2.jar";
        name   = "Glassential-renewed-1.21.1-3.4.2.jar";
        sha256 = "0niw0iqan9sh6rcwy6qlmv51l0810id44kid8x3niw9xk8ss148x";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 306770;
      origFileID    = 6842247;
      projectID     = 306770;
      fileID        = 7730942;
      required      = true;
      filename      = "Patchouli-1.21.1-93-NEOFORGE.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7730/942/Patchouli-1.21.1-93-NEOFORGE.jar";
        name   = "Patchouli-1.21.1-93-NEOFORGE.jar";
        sha256 = "14zrv7sligw3pa83hq6n3ahywjmy40s20sc479n32334sqpgb6lm";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1160104;
      origFileID    = 6781033;
      projectID     = 1160104;
      fileID        = 7263416;
      required      = true;
      filename      = "aero_additions-1.2.7.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7263/416/aero_additions-1.2.7.jar";
        name   = "aero_additions-1.2.7.jar";
        sha256 = "0lg65jr0f587qxrs98z47dd245kwwkfq0i05pvidfcvyhdz5dg1d";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 248787;
      origFileID    = 6616291;
      projectID     = 248787;
      fileID        = 7854442;
      required      = true;
      filename      = "appleskin-neoforge-mc1.21-3.0.9.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7854/442/appleskin-neoforge-mc1.21-3.0.9.jar";
        name   = "appleskin-neoforge-mc1.21-3.0.9.jar";
        sha256 = "1pr277xvln8a74wckgkjiz6ccrn8gv2l4vnfckwwjh8k4gb8vd1q";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 978125;
      origFileID    = 6667255;
      projectID     = 978125;
      fileID        = 8038954;
      required      = true;
      filename      = "create_ultimate_factory-2.2.4-neoforge-1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8038/954/create_ultimate_factory-2.2.4-neoforge-1.21.1.jar";
        name   = "create_ultimate_factory-2.2.4-neoforge-1.21.1.jar";
        sha256 = "1c511wgbxl2fnaq6ilvmx2hqfq928962nfzk4lcaz7l57kacspdr";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1231381;
      origFileID    = 6760692;
      projectID     = 1231381;
      fileID        = 8042566;
      required      = true;
      filename      = "createultimine-1.21.1-neoforge-1.3.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8042/566/createultimine-1.21.1-neoforge-1.3.1.jar";
        name   = "createultimine-1.21.1-neoforge-1.3.1.jar";
        sha256 = "00hl3pk6ggw2fda5x72yhdd9vdq7jhakvqjwia37g7rq0gkvwmxd";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 871755;
      origFileID    = 6678572;
      projectID     = 871755;
      fileID        = 7862664;
      required      = true;
      filename      = "exposure-neoforge-1.21.1-1.9.16.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7862/664/exposure-neoforge-1.21.1-1.9.16.jar";
        name   = "exposure-neoforge-1.21.1-1.9.16.jar";
        sha256 = "0n5vlan5wj9l4bzk3kdkj696pjfp406vz64c03h4rkwlc0sgxbf4";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1083998;
      origFileID    = 6951634;
      projectID     = 1083998;
      fileID        = 7850813;
      required      = true;
      filename      = "fantasy_armor-neoforge-1.2.4-1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7850/813/fantasy_armor-neoforge-1.2.4-1.21.1.jar";
        name   = "fantasy_armor-neoforge-1.2.4-1.21.1.jar";
        sha256 = "19bkf29srq1i0xpgmzrh6j5f9bxy4s16ppahvdvi9f9dp92n8k2c";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 238551;
      origFileID    = 7099728;
      projectID     = 238551;
      fileID        = 8056307;
      required      = true;
      filename      = "gravestone-neoforge-1.21.1-1.0.37.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8056/307/gravestone-neoforge-1.21.1-1.0.37.jar";
        name   = "gravestone-neoforge-1.21.1-1.0.37.jar";
        sha256 = "0gjsplrrk2k3s6vzky5h6b7k9x4r2qhasimiy8df8d8zpzn5vpmp";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 639584;
      origFileID    = 6679636;
      projectID     = 639584;
      fileID        = 7583940;
      required      = true;
      filename      = "immersive_paintings-neoforge-1.21.1-0.7.6.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7583/940/immersive_paintings-neoforge-1.21.1-0.7.6.jar";
        name   = "immersive_paintings-neoforge-1.21.1-0.7.6.jar";
        sha256 = "1x6yr3l0wpfviapqihgmd7y7chd16fdjngx89x6gxxkmym2hpkj8";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 368825;
      origFileID    = 6794130;
      projectID     = 368825;
      fileID        = 8019500;
      required      = true;
      filename      = "inventoryessentials-neoforge-1.21.1-21.1.15.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8019/500/inventoryessentials-neoforge-1.21.1-21.1.15.jar";
        name   = "inventoryessentials-neoforge-1.21.1-21.1.15.jar";
        sha256 = "0pl87c44sfg9xf5z7187z8ihnl98ivmksp1kf9q3c7l56v0c1w9g";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1062363;
      origFileID    = 6943627;
      projectID     = 1062363;
      fileID        = 7751818;
      required      = true;
      filename      = "letsdo-furniture-neoforge-1.1.4.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7751/818/letsdo-furniture-neoforge-1.1.4.jar";
        name   = "letsdo-furniture-neoforge-1.1.4.jar";
        sha256 = "0m3f34v2lxap7cw1k87mmj05ndvr2dakrys44n6n7vq28j7954f2";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 936015;
      origFileID    = 6743507;
      projectID     = 936015;
      fileID        = 8056160;
      required      = true;
      filename      = "lithostitched-1.7.3-neoforge-21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8056/160/lithostitched-1.7.3-neoforge-21.1.jar";
        name   = "lithostitched-1.7.3-neoforge-21.1.jar";
        sha256 = "0lskjc21l5pv543ffhb93hlirxpi7qhd2kbilqa0hnx3y65v830x";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1134260;
      origFileID    = 6168640;
      projectID     = 1134260;
      fileID        = 7920425;
      required      = true;
      filename      = "lootintegrations_cataclysm-1.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7920/425/lootintegrations_cataclysm-1.2.jar";
        name   = "lootintegrations_cataclysm-1.2.jar";
        sha256 = "0f35mrw25za55913h2agflsa9km0ihq52qggi8mjwgz3agyqzbhx";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1139414;
      origFileID    = 6509967;
      projectID     = 1139414;
      fileID        = 7915316;
      required      = true;
      filename      = "lootintegrations_dnt-2.5.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7915/316/lootintegrations_dnt-2.5.jar";
        name   = "lootintegrations_dnt-2.5.jar";
        sha256 = "0zdy2g0sndgvv793vq3vld078yz6s43qgyrrgkicq9mn79arrjyq";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 1269720;
      origFileID    = 6550111;
      projectID     = 1269720;
      fileID        = 7925171;
      required      = true;
      filename      = "lootintegrations_stellarity-1.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7925/171/lootintegrations_stellarity-1.1.jar";
        name   = "lootintegrations_stellarity-1.1.jar";
        sha256 = "13qdg9vb71zsk0av276r0ah6lpwpk84mn6qpnxysarxmprz0qyia";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 659887;
      origFileID    = 6751823;
      projectID     = 659887;
      fileID        = 6958145;
      required      = true;
      filename      = "simplyswords-neoforge-1.62.0-1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/6958/145/simplyswords-neoforge-1.62.0-1.21.1.jar";
        name   = "simplyswords-neoforge-1.62.0-1.21.1.jar";
        sha256 = "16jmc2s4xywn96rkfbwyqhhwi1ayxmaddkqzv13gjfcrvyzaky82";
      };
    }
    {
      # Bump (find-mod-bumps, safe-curated set).
      origProjectID = 245755;
      origFileID    = 7966157;
      projectID     = 245755;
      fileID        = 8056467;
      required      = true;
      filename      = "waystones-neoforge-1.21.1-21.1.32.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8056/467/waystones-neoforge-1.21.1-21.1.32.jar";
        name   = "waystones-neoforge-1.21.1-21.1.32.jar";
        sha256 = "1ph1khf6r2majsa3km6s0ji68w1kqs3fkxdk13z7svlyxrzcpayl";
      };
    }

    {
      # Bumped by find-mod-bumps (sophisticatedcore).
      origProjectID = 618298;
      origFileID    = 6933219;
      projectID     = 618298;
      fileID        = 8084486;
      required      = true;
      filename      = "sophisticatedcore-1.21.1-1.4.39.1852.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8084/486/sophisticatedcore-1.21.1-1.4.39.1852.jar";
        name   = "sophisticatedcore-1.21.1-1.4.39.1852.jar";
        sha256 = "1z2jilj2vfz4gdbjrwiqfzjynvd3fbgxcjg9pcbmxvfy9fc0vvq1";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1316458;
      origFileID    = 6824093;
      projectID     = 1316458;
      fileID        = 8059464;
      required      = true;
      filename      = "familiarslib-1.21.1-1.7.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8059/464/familiarslib-1.21.1-1.7.1.jar";
        name   = "familiarslib-1.21.1-1.7.1.jar";
        sha256 = "1ag5l2cr4nyqkmwx7lmv83hibfjxsxl9qqdk5n5jc312pd4bqlxz";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1264423;
      origFileID    = 6882611;
      projectID     = 1264423;
      fileID        = 7880467;
      required      = true;
      filename      = "baguettelib-1.21.1-NeoForge-2.0.3.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7880/467/baguettelib-1.21.1-NeoForge-2.0.3.jar";
        name   = "baguettelib-1.21.1-NeoForge-2.0.3.jar";
        sha256 = "1rgi22j11i9zg8scf74ri1qvy5v2yjldwz7k1vsd94hyifvdzbcq";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1194714;
      origFileID    = 6164512;
      projectID     = 1194714;
      fileID        = 7584985;
      required      = true;
      filename      = "gtbcs_spell_lib-1.5.0-1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7584/985/gtbcs_spell_lib-1.5.0-1.21.1.jar";
        name   = "gtbcs_spell_lib-1.5.0-1.21.1.jar";
        sha256 = "1j5if628qf3gwvb940pirr4kvc5r61bglsmpxfphppgvn1lakp9h";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1115285;
      origFileID    = 5803531;
      projectID     = 1115285;
      fileID        = 7489091;
      required      = true;
      filename      = "Almanac-1.21.1-2-neoforge-1.5.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7489/91/Almanac-1.21.1-2-neoforge-1.5.2.jar";
        name   = "Almanac-1.21.1-2-neoforge-1.5.2.jar";
        sha256 = "1jxa4acbx0bygfyvim9bikh3as6d97ii31saivfsdaikdhj9761p";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1072905;
      origFileID    = 6843052;
      projectID     = 1072905;
      fileID        = 7738312;
      required      = true;
      filename      = "jupiter-2.3.7-1.21.1-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7738/312/jupiter-2.3.7-1.21.1-neoforge.jar";
        name   = "jupiter-2.3.7-1.21.1-neoforge.jar";
        sha256 = "05ff79lhnsvm6fzli0rq79kndhjp41mzx26jv7i7zyahy8m37bwm";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1010827;
      origFileID    = 6919185;
      projectID     = 1010827;
      fileID        = 8008516;
      required      = true;
      filename      = "uranus-2.4.1-1.21.1-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8008/516/uranus-2.4.1-1.21.1-neoforge.jar";
        name   = "uranus-2.4.1-1.21.1-neoforge.jar";
        sha256 = "07hxivaviypmmswfjj1w681qisj686kn2dbhpzqb3kxwafrsjmi1";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 448233;
      origFileID    = 6780238;
      projectID     = 448233;
      fileID        = 8053771;
      required      = true;
      filename      = "entityculling-neoforge-1.10.2-mc1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8053/771/entityculling-neoforge-1.10.2-mc1.21.1.jar";
        name   = "entityculling-neoforge-1.10.2-mc1.21.1.jar";
        sha256 = "1k860cmi1yq2apr9xlpgbana917g141ffr5piqn3p66vivqls090";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 326652;
      origFileID    = 6078150;
      projectID     = 326652;
      fileID        = 7746488;
      required      = true;
      filename      = "cupboard-1.21-3.5.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7746/488/cupboard-1.21-3.5.jar";
        name   = "cupboard-1.21-3.5.jar";
        sha256 = "1ny79535hi717cws053g7vrr7ywwyihbss8qvxdwkmklgnv9hwnj";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 404465;
      origFileID    = 6874538;
      projectID     = 404465;
      fileID        = 7746959;
      required      = true;
      filename      = "ftb-library-neoforge-2101.1.31.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7746/959/ftb-library-neoforge-2101.1.31.jar";
        name   = "ftb-library-neoforge-2101.1.31.jar";
        sha256 = "1swav05y9avw9zdfd1cpd2q846s9w29llj3dw118i4yghx8p0i1x";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1299492;
      origFileID    = 6925303;
      projectID     = 1299492;
      fileID        = 8079666;
      required      = true;
      filename      = "aces_spell_utils-1.2.6.1-1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8079/666/aces_spell_utils-1.2.6.1-1.21.1.jar";
        name   = "aces_spell_utils-1.2.6.1-1.21.1.jar";
        sha256 = "1qjkxngif3iq746zhjvwky3z4xqgmxbygr0dsvr9wp6nsijj7svg";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 410811;
      origFileID    = 6179042;
      projectID     = 410811;
      fileID        = 7608733;
      required      = true;
      filename      = "ftb-essentials-neoforge-2101.1.9.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7608/733/ftb-essentials-neoforge-2101.1.9.jar";
        name   = "ftb-essentials-neoforge-2101.1.9.jar";
        sha256 = "1gqrq9bcncbjg1vyn264rlrb2fa2w9gjc1b7dxg1mvyfc7af9a2d";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 855414;
      origFileID    = 6932556;
      projectID     = 855414;
      fileID        = 7691161;
      required      = true;
      filename      = "irons_spellbooks-1.21.1-3.15.4.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7691/161/irons_spellbooks-1.21.1-3.15.4.jar";
        name   = "irons_spellbooks-1.21.1-3.15.4.jar";
        sha256 = "188q8i1w4p23cgi245wi7xhywx4xcsrnaigdmd344sw4irw7v9h3";
      };
    }
    {
      # Bumped by find-mod-bumps (sophisticatedstorage).
      origProjectID = 619320;
      origFileID    = 6912198;
      projectID     = 619320;
      fileID        = 8084562;
      required      = true;
      filename      = "sophisticatedstorage-1.21.1-1.5.47.1724.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8084/562/sophisticatedstorage-1.21.1-1.5.47.1724.jar";
        name   = "sophisticatedstorage-1.21.1-1.5.47.1724.jar";
        sha256 = "19y14fzsb5q4j9q40j5rbdp2vmm458qk9rvnsd32qm0gbwww4psm";
      };
    }
    {
      # Bumped by find-mod-bumps (sophisticatedbackpacks).
      origProjectID = 422301;
      origFileID    = 6907846;
      projectID     = 422301;
      fileID        = 8084526;
      required      = true;
      filename      = "sophisticatedbackpacks-1.21.1-3.25.45.1742.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8084/526/sophisticatedbackpacks-1.21.1-3.25.45.1742.jar";
        name   = "sophisticatedbackpacks-1.21.1-3.25.45.1742.jar";
        sha256 = "0zw86f5b58f0m66lqzgbchb3hvyng8ymsv4xr41v0xdisy86zx6v";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1226755;
      origFileID    = 6569224;
      projectID     = 1226755;
      fileID        = 7974820;
      required      = true;
      filename      = "sophisticatedstoragecreateintegration-1.21.1-0.1.17.132.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7974/820/sophisticatedstoragecreateintegration-1.21.1-0.1.17.132.jar";
        name   = "sophisticatedstoragecreateintegration-1.21.1-0.1.17.132.jar";
        sha256 = "15cjly625i0xlxs9fmrpwza3cdzviq4af897pg78jhbwpjba5f6x";
      };
    }
    {
      # Bump bundle (find-mod-bumps -46).
      origProjectID = 1238567;
      origFileID    = 6569915;
      projectID     = 1238567;
      fileID        = 7168412;
      required      = true;
      filename      = "sophisticatedbackpackscreateintegration-1.21.1-0.1.5.29.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7168/412/sophisticatedbackpackscreateintegration-1.21.1-0.1.5.29.jar";
        name   = "sophisticatedbackpackscreateintegration-1.21.1-0.1.5.29.jar";
        sha256 = "1smr8jzlb0gf4wl8w2pi99zybvv02hyxlfdjvinygkx45g0abpdp";
      };
    }

    {
      # Bump bundle: paired with familiarslib 1.0.0 → 1.7.1
      # to keep ABI alignment (familiarslib removed AbstractConsumableItem).
      origProjectID = 1171602;
      origFileID    = 6825732;
      projectID     = 1171602;
      fileID        = 8059472;
      required      = true;
      filename      = "alshanex_familiars-1.21.1_v4.0.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8059/472/alshanex_familiars-1.21.1_v4.0.2.jar";
        name   = "alshanex_familiars-1.21.1_v4.0.2.jar";
        sha256 = "06q7ck1wrnnqbgsj2dxizx13z771bb3gj3scrh0a525ch69mrrj7";
      };
    }

      {
      # Bumped by find-mod-bumps (beautiful_potions).
      origProjectID = 1298070;
      origFileID    = 6953563;
      projectID     = 1298070;
      fileID        = 7952054;
      required      = true;
      filename      = "BTP-NeoForge-1.21.1-2.0.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7952/54/BTP-NeoForge-1.21.1-2.0.0.jar";
        name   = "BTP-NeoForge-1.21.1-2.0.0.jar";
        sha256 = "0pknzyaxgba9ilmnwf45x96ny6l8v0b7p3148fwxan7rvwg4zyfk";
      };
    }
    {
      # Bumped by find-mod-bumps (beb).
      origProjectID = 1083202;
      origFileID    = 6726136;
      projectID     = 1083202;
      fileID        = 7268159;
      required      = true;
      filename      = "BEB-NeoForge-1.21-6.0.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7268/159/BEB-NeoForge-1.21-6.0.0.jar";
        name   = "BEB-NeoForge-1.21-6.0.0.jar";
        sha256 = "19ibkkzkqizrpm9is5ws60cwprrr9zaxpyl8v11i8j44jsggwcgv";
      };
    }
    {
      # Bumped by find-mod-bumps (betterarcheology).
      origProjectID = 835687;
      origFileID    = 6423649;
      projectID     = 835687;
      fileID        = 7756575;
      required      = true;
      filename      = "betterarcheology-neoforge-1.21.1-1.3.4.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7756/575/betterarcheology-neoforge-1.21.1-1.3.4.jar";
        name   = "betterarcheology-neoforge-1.21.1-1.3.4.jar";
        sha256 = "1i1p21mas5knzwksrwh24yiaramnw1096cr7hxxrbv8svrfvkdg0";
      };
    }
    {
      # Bumped by find-mod-bumps (craftingtweaks).
      origProjectID = 233071;
      origFileID    = 6784518;
      projectID     = 233071;
      fileID        = 8019498;
      required      = true;
      filename      = "craftingtweaks-neoforge-1.21.1-21.1.10.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8019/498/craftingtweaks-neoforge-1.21.1-21.1.10.jar";
        name   = "craftingtweaks-neoforge-1.21.1-21.1.10.jar";
        sha256 = "1c33pvxjc0hqfvl5ss04w05gd1zs8gzsmjmhcy2zpxw94cnf5dg3";
      };
    }
    {
      # Bumped by find-mod-bumps (create_wizardry).
      origProjectID = 949995;
      origFileID    = 6845541;
      projectID     = 949995;
      fileID        = 7811721;
      required      = true;
      filename      = "create_wizardry-1.21.1-0.4.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7811/721/create_wizardry-1.21.1-0.4.2.jar";
        name   = "create_wizardry-1.21.1-0.4.2.jar";
        sha256 = "167xwbbxc30p0p9py54f56djx7b279rc2pdqwcd8rdfkqr77syjd";
      };
    }
    {
      # Bumped by find-mod-bumps (darkdoppelganger).
      origProjectID = 1110803;
      origFileID    = 6671169;
      projectID     = 1110803;
      fileID        = 7759880;
      required      = true;
      filename      = "darkdoppelganger-3.3.0-1.21.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7759/880/darkdoppelganger-3.3.0-1.21.1.jar";
        name   = "darkdoppelganger-3.3.0-1.21.1.jar";
        sha256 = "1lss5ijgz3pd5yriz3fzpagbwi73i4l8mwf0gyfv31k8bvh7905c";
      };
    }
    {
      # Bumped by find-mod-bumps (deeperdarker).
      origProjectID = 659011;
      origFileID    = 6463247;
      projectID     = 659011;
      fileID        = 7940538;
      required      = true;
      filename      = "deeperdarker-neoforge-1.21.1-1.4.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7940/538/deeperdarker-neoforge-1.21.1-1.4.jar";
        name   = "deeperdarker-neoforge-1.21.1-1.4.jar";
        sha256 = "1qjmbcxb1qca6mh56zma3aigsgqpz129l21icax1zhs4fr3bxf8s";
      };
    }
    {
      # Bumped by find-mod-bumps (dynamic_difficulty).
      origProjectID = 1272655;
      origFileID    = 6940848;
      projectID     = 1272655;
      fileID        = 7276221;
      required      = true;
      filename      = "dynamic_difficulty-0.9.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7276/221/dynamic_difficulty-0.9.1.jar";
        name   = "dynamic_difficulty-0.9.1.jar";
        sha256 = "1gc1z0hi6zdc5zjc211nka1whkimjycf79c3i5ax6sa904y11px9";
      };
    }
    {
      # Bumped by find-mod-bumps (ess_requiem).
      origProjectID = 1336977;
      origFileID    = 6948627;
      projectID     = 1336977;
      fileID        = 7932825;
      required      = true;
      filename      = "ess_requiem-0.1.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7932/825/ess_requiem-0.1.2.jar";
        name   = "ess_requiem-0.1.2.jar";
        sha256 = "0j7nqyh5rabr8ln9jvxlsygvrlicrh5lysadk9pc48s6fyssrand";
      };
    }
    {
      # Bumped by find-mod-bumps (firesenderexpansion).
      origProjectID = 1245989;
      origFileID    = 6932708;
      projectID     = 1245989;
      fileID        = 7804733;
      required      = true;
      filename      = "firesenderexpansion-2.3.5.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7804/733/firesenderexpansion-2.3.5.jar";
        name   = "firesenderexpansion-2.3.5.jar";
        sha256 = "0vqbicvvc9z57a4d6xwc9a486wbjkidb0xrwyr1k7hcrcjavr9d2";
      };
    }
    {
      # Bumped by find-mod-bumps (ftbchunks).
      origProjectID = 314906;
      origFileID    = 6900454;
      projectID     = 314906;
      fileID        = 7157142;
      required      = true;
      filename      = "ftb-chunks-neoforge-2101.1.13.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7157/142/ftb-chunks-neoforge-2101.1.13.jar";
        name   = "ftb-chunks-neoforge-2101.1.13.jar";
        sha256 = "0l3c71gdaas2r2kqka36n5s81xpis2jj185rz17i7mlfcrlvbw6h";
      };
    }
    {
      # Bumped by find-mod-bumps (gag).
      origProjectID = 694962;
      origFileID    = 6945014;
      projectID     = 694962;
      fileID        = 7261542;
      required      = true;
      filename      = "gag-neoforge-1.21.1-5.2.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7261/542/gag-neoforge-1.21.1-5.2.0.jar";
        name   = "gag-neoforge-1.21.1-5.2.0.jar";
        sha256 = "15cz34694b3gwzxh378b8mylm5p0qlrkfzb80qh26s9az91b1qp8";
      };
    }
    {
      # Bumped by find-mod-bumps (gravestonecurioscompat).
      origProjectID = 1139062;
      origFileID    = 6555981;
      projectID     = 1139062;
      fileID        = 7891807;
      required      = true;
      filename      = "gravestonecurioscompat-1.21.1-NeoForge-4.0.2.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7891/807/gravestonecurioscompat-1.21.1-NeoForge-4.0.2.jar";
        name   = "gravestonecurioscompat-1.21.1-NeoForge-4.0.2.jar";
        sha256 = "119jhb7k13zpqggg05mag680y0151pr3v7frc6zxqm57fjrrz1nq";
      };
    }
    {
      # Bumped by find-mod-bumps (iceandfire).
      origProjectID = 1040076;
      origFileID    = 6947928;
      projectID     = 1040076;
      fileID        = 8031633;
      required      = true;
      filename      = "IceAndFireCE-2.0-beta.16-1.21.1-neoforge.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8031/633/IceAndFireCE-2.0-beta.16-1.21.1-neoforge.jar";
        name   = "IceAndFireCE-2.0-beta.16-1.21.1-neoforge.jar";
        sha256 = "08z22i2q3dhbjcf2v3badszpqwnl28m27q8z4bix1paffg5jcqwv";
      };
    }
    {
      # Bumped by find-mod-bumps (irons_jewelry).
      origProjectID = 1101111;
      origFileID    = 6880791;
      projectID     = 1101111;
      fileID        = 7358426;
      required      = true;
      filename      = "irons_jewelry-1.21.1-1.6.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7358/426/irons_jewelry-1.21.1-1.6.0.jar";
        name   = "irons_jewelry-1.21.1-1.6.0.jar";
        sha256 = "1213znzcf5f7z3jsi725dgiqfxgg1zsbjrpajyrqj8ydypgphdbb";
      };
    }
    {
      # Bumped by find-mod-bumps (moonlight).
      origProjectID = 499980;
      origFileID    = 6939532;
      projectID     = 499980;
      fileID        = 8065893;
      required      = true;
      filename      = "moonlight-neoforge-1.21.1-3.0.7.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/8065/893/moonlight-neoforge-1.21.1-3.0.7.jar";
        name   = "moonlight-neoforge-1.21.1-3.0.7.jar";
        sha256 = "1lq98bybn4l0nny9kfg69kxvsjwv5w50xqdh9k3k8nx8ja7wa9qh";
      };
    }
    {
      # Bumped by find-mod-bumps (reliquified_twilight_forest).
      origProjectID = 1186617;
      origFileID    = 6880511;
      projectID     = 1186617;
      fileID        = 7680883;
      required      = true;
      filename      = "reliquified_twilight_forest-1.21.1-0.5.3.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7680/883/reliquified_twilight_forest-1.21.1-0.5.3.jar";
        name   = "reliquified_twilight_forest-1.21.1-0.5.3.jar";
        sha256 = "1qx9ars6ai9jwm6j9nxlmw4m90d7hf2xvw3crrzgf29q1hqxg29c";
      };
    }
    {
      # Bumped by find-mod-bumps (simplymore).
      origProjectID = 1095252;
      origFileID    = 6879511;
      projectID     = 1095252;
      fileID        = 6958385;
      required      = true;
      filename      = "simplymore-forge-1.2.1.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/6958/385/simplymore-forge-1.2.1.jar";
        name   = "simplymore-forge-1.2.1.jar";
        sha256 = "0i735widsx927lnigbf8qc2yq2jp9lz4k28r9gkzf020kdsij0fb";
      };
    }
    {
      # Bumped by find-mod-bumps (subtle_effects).
      origProjectID = 1023913;
      origFileID    = 6857391;
      projectID     = 1023913;
      fileID        = 7064187;
      required      = true;
      filename      = "SubtleEffects-neoforge-1.21.1-1.13.0.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7064/187/SubtleEffects-neoforge-1.21.1-1.13.0.jar";
        name   = "SubtleEffects-neoforge-1.21.1-1.13.0.jar";
        sha256 = "186qwraf8zyizh8ah85ygcmgrr0napaadjm68vhjz6hdm4wbnp6c";
      };
    }
    {
      # Bumped by find-mod-bumps (twilightforest).
      origProjectID = 227639;
      origFileID    = 6472889;
      projectID     = 227639;
      fileID        = 7797302;
      required      = true;
      filename      = "twilightforest-1.21.1-4.8.3345-universal.jar";
      jar = fetchurl {
        url    = "https://mediafilez.forgecdn.net/files/7797/302/twilightforest-1.21.1-4.8.3345-universal.jar";
        name   = "twilightforest-1.21.1-4.8.3345-universal.jar";
        sha256 = "0ddskayn4ic97ishshpf2r0b3saarf7ksfy3ld9ry3r121ns2ga9";
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
    { projectID = 820977;  fileID = null; reason = "Incompatible with Create Aeronautics"; phase = "worldgen"; }
    # create_dragons_plus 1.7.0 was disabled (PotionMixingRecipesMixin
    # referenced removed Create FluidIngredient); replaced with 1.10.0
    # above (built against Create 6.0.10) instead.
    { projectID = 688768; fileID = null; reason = "Incompatible with Create Aeronautics"; phase = "worldgen"; }
    # LeavesBeGone registers a per-chunk leaf-decay tick container during
    # chunk init. Sable's physics engine builds a fresh ServerSubLevel
    # mini-dimension on Aeronautics ship-assemble, and the chunks born
    # there don't have their `randomBlockTicks` list populated yet at the
    # moment LeavesBeGone's chunk-init hook fires → NPE:
    #   Caused by: java.lang.NullPointerException: Random block ticks was null
    #     at LeavesBeGone$ChunkInitHandler...
    # Aeronautics ship-assemble silently fails (blocks stay as blocks).
    # No upstream fix; LeavesBeGone author hasn't shipped null-guarded
    # handler. Drop the mod — purely-cosmetic decay-speedup feature, low
    # blast radius without it.
    { projectID = 686435; fileID = null; reason = "LeavesBeGone NPE on Sable physics ServerSubLevel chunk init (randomBlockTicks null) breaks Aeronautics ship-assemble."; phase = "runtime"; }
    # User opted to drop Herbal Brews entirely after the
    # tea-blossom-on-fortune loot-table bug. The shears-only datapack
    # fix is removed alongside the mod (no need without it). No cascade
    # — Herbal Brews is a Let's Do leaf addon, not depended on by other
    # mods in the pack (the rest of Let's Do family was already
    # disabled in the farm_and_charm cluster).
    { projectID = 951221; fileID = null; reason = "User opted to drop Herbal Brews entirely (vanilla-flower loot-table bugs)."; phase = "runtime"; }
  ];
}
