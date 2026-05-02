# AUTO-GENERATED — see scripts under /tmp/build_v106.sh + prefetch_v106.sh
# Mod-jar overlays from Create Sky Colonies v1.06 client pack (publisher
# has not released a v1.06 server pack yet, so we patch v1.05 server in
# place with v1.06 mod versions for the 17 server-side mods that bumped).
{ fetchurl }:
[
  {
    # byzantine: v1.05 -> v1.06
    v105Filename = "Byzantine-1.21.1-44.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7343/110/Byzantine-1.21.1-46.jar";
      sha256 = "090bsn6m1wlgsdlcc63kbkjk0i7piarg012m2yl36knl1m7faybr";
    };
    v106Filename = "Byzantine-1.21.1-46.jar";
  }
  {
    # createschematicchecker: v1.05 -> v1.06
    v105Filename = "CreateSchematicChecker-0.21.12-6.0-forge-1.20.1.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7420/638/CreateSchematicChecker-0.21.13-6.0-forge-1.20.1.jar";
      sha256 = "14h3sqkh6l98k1csl8fx9yy66iwkjm4fi9vz07wga6khab7g53yz";
    };
    v106Filename = "CreateSchematicChecker-0.21.13-6.0-forge-1.20.1.jar";
  }
  {
    # fastsuite: v1.05 -> v1.06
    v105Filename = "FastSuite-1.20.1-5.1.0.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7428/292/FastSuite-1.20.1-5.1.1.jar";
      sha256 = "04vmnmzw90c89i5zhc25c7adhy9gwav4zafqrk6w3h2i6plax659";
    };
    v106Filename = "FastSuite-1.20.1-5.1.1.jar";
  }
  {
    # minecolonies_compatibility: v1.05 -> v1.06
    v105Filename = "MineColonies_Compatibility-1.20.1-2.105.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7463/731/MineColonies_Compatibility-1.20.1-2.108.jar";
      sha256 = "03rfi615pllpl7sd0mz3ywpzhbv0xqdk49lj78n9yy8vm4gvl7kr";
    };
    v106Filename = "MineColonies_Compatibility-1.20.1-2.108.jar";
  }
  {
    # minecolonies_tweaks: v1.05 -> v1.06
    v105Filename = "MineColonies_Tweaks-1.20.1-2.93-all.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7463/670/MineColonies_Tweaks-1.20.1-2.96-all.jar";
      sha256 = "0m3n8wqqnawplzp3ch2f5xy4rqdfa8wdkdwp5g56kz0fgzxapy0z";
    };
    v106Filename = "MineColonies_Tweaks-1.20.1-2.96-all.jar";
  }
  {
    # bits-and-bobs: v1.05 -> v1.06
    v105Filename = "bits-and-bobs-1.20.1-0.1.1.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7449/119/bits-and-bobs-1.20.1-0.1.2.jar";
      sha256 = "1qs1s3sxajhlsv3wr0c9vygq4889wrs6sjzch32jjqmn13bq8anj";
    };
    v106Filename = "bits-and-bobs-1.20.1-0.1.2.jar";
  }
  {
    # bits_n_bobs: v1.05 -> v1.06
    v105Filename = "bits_n_bobs-0.0.40.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7427/192/bits_n_bobs-0.0.41.jar";
      sha256 = "0v1g0ccr91hxlsh8704sq9wff6dv77chr6zvijw1gygdb2dp4683";
    };
    v106Filename = "bits_n_bobs-0.0.41.jar";
  }
  {
    # create_ltab: v1.05 -> v1.06
    v105Filename = "create_ltab-3.6.0.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7451/346/create_ltab-3.6.2.jar";
      sha256 = "0mmqq91yl0b4xixsyf94fg161kdw4ildn6jadn1x2snwr8lnb30j";
    };
    v106Filename = "create_ltab-3.6.2.jar";
  }
  {
    # create_structures_overhaul: v1.05 -> v1.06
    v105Filename = "create_structures_overhaul-1.4.0.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7462/722/create_structures_overhaul-1.4.1.jar";
      sha256 = "1vxm2vfmg2l3fgz6mkzbccb8h58jh8c4sp6nfa7k078jpn0am6r4";
    };
    v106Filename = "create_structures_overhaul-1.4.1.jar";
  }
  {
    # domum_ornamentum: v1.05 -> v1.06
    v105Filename = "domum_ornamentum-1.20.1-1.0.292-snapshot-universal.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7421/161/domum_ornamentum-1.20.1-1.0.295-snapshot-universal.jar";
      sha256 = "06lgp9gwcdiffryh6ksfwapfgrfxfvpal592y631mc5wgv0r20y1";
    };
    v106Filename = "domum_ornamentum-1.20.1-1.0.295-snapshot-universal.jar";
  }
  {
    # floating_islands: v1.05 -> v1.06
    v105Filename = "floating_islands-1.4.1.1.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7419/586/floating_islands-1.4.1.2.jar";
      sha256 = "0wq408xzmw0l9zzw7n44b573swv8hlxflccqdsv5i7hgxr111ayx";
    };
    v106Filename = "floating_islands-1.4.1.2.jar";
  }
  {
    # fusion: v1.05 -> v1.06
    v105Filename = "fusion-1.2.11c-forge-mc1.20.1.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7471/518/fusion-1.2.12-forge-mc1.20.1.jar";
      sha256 = "0pmlbx85c81dlqzl2j2gzcjr0msrhx54h3nm0n3npbh85s93kc2w";
    };
    v106Filename = "fusion-1.2.12-forge-mc1.20.1.jar";
  }
  {
    # minecolonies: v1.05 -> v1.06
    v105Filename = "minecolonies-1.20.1-1.1.1155-snapshot.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7450/499/minecolonies-1.20.1-1.1.1161-snapshot.jar";
      sha256 = "0g7nyxhmqmmhfr9xdrk0nn88iqvi0y0sw22zg02mcijxi91x3m3l";
    };
    v106Filename = "minecolonies-1.20.1-1.1.1161-snapshot.jar";
  }
  {
    # rusticdelight: v1.05 -> v1.06
    v105Filename = "rusticdelight-forge-1.20.1-1.4.1.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7456/148/rusticdelight-forge-1.20.1-1.5.0.jar";
      sha256 = "1dp70zvvdbwrgxbvyvbx08j09fr7fa0wgy7q1nm78ghhdcq189yl";
    };
    v106Filename = "rusticdelight-forge-1.20.1-1.5.0.jar";
  }
  {
    # structurize: v1.05 -> v1.06
    v105Filename = "structurize-1.20.1-1.0.793-snapshot.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7427/219/structurize-1.20.1-1.0.797-snapshot.jar";
      sha256 = "0mxx1fzlvm9281m9x8931pgj5d05gv3pgzqgj7ri97awmq8nzc7q";
    };
    v106Filename = "structurize-1.20.1-1.0.797-snapshot.jar";
  }
  {
    # stylecolonies: v1.05 -> v1.06
    v105Filename = "stylecolonies-1.20.1-1.15.50.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7450/495/stylecolonies-1.20.1-1.15.52.jar";
      sha256 = "1j7aan0ngqxvnb9hg6zm2lgmf4gdhn9cbic1vdgamh226iajvmg3";
    };
    v106Filename = "stylecolonies-1.20.1-1.15.52.jar";
  }
  {
    # supplylines: v1.05 -> v1.06
    v105Filename = "supplylines-mc1.20.1-1.1.0-alpha.3.jar";
    v106Jar = fetchurl {
      url = "https://mediafilez.forgecdn.net/files/7476/874/supplylines-mc1.20.1-1.3.0-beta.2.jar";
      sha256 = "0b53zhli2acv7ljdih9z4hhi8kd0iwapxha2xy5rpx7gk2m4qcw3";
    };
    v106Filename = "supplylines-mc1.20.1-1.3.0-beta.2.jar";
  }
]
