# Resource packs bundled into the client zip. OpenLoader auto-loads zips
# from <game-dir>/openloader/resources/ at the highest priority, so players
# don't have to toggle anything in Options → Resource Packs. Server tree
# doesn't ship these — resource packs are client-side art only; the
# dedicated server has no use for them.
#
# Each entry: { filename = "..."; zip = <derivation>; }. `filename` is the
# on-disk name inside overrides/openloader/resources/.
#
# Selection rationale (Arkana + Aeronautics, 1.21.1, NeoForge):
#   * Stay True            — 16x vanilla-faithful base pack. Closest match
#                            to Arkana's stock look; widely supported by
#                            compat addons.
#   * Stay True Compats    — official mod-compat addon. Covers Create,
#                            Farmer's Delight, Quark, Biomes O'Plenty,
#                            Abnormals stack — the modded blocks that
#                            most often look out-of-place against Stay
#                            True's retextured vanilla blocks.
#   * Fresh Animations     — mob animation overhaul for vanilla mobs.
#                            Modded mobs are untouched (acceptable; modded
#                            mobs aren't animated by the default look
#                            either). Requires Entity Model Features
#                            (already shipped client-side via Arkana's
#                            manifest).
#   * Create: Fresh Items  — 3D item models for Create's contraption +
#                            material items. Orthogonal to base pack.
#
# Pack precedence: OpenLoader stacks alphabetically (later overrides
# earlier). Filenames are prefixed with `01-`, `02-`, … to make the
# stacking order explicit — base first, compat addon next, then the
# orthogonal Fresh Animations / Create: Fresh Items packs on top.
#
# Some upstream packs ship with an `mcmeta` that doesn't advertise
# compatibility with the modpack's MC version (1.21.1 / pack_format 34),
# even though their content is just textures and works fine. The
# `patchMcmeta` helper below wraps such a pack: fetch upstream, edit
# pack.mcmeta to widen `supported_formats`, rezip. Reproducible.
{ fetchurl, stdenvNoCC, unzip, zip, jq }:
let
  # Build-time patch: fetches `src`, replaces `pack.mcmeta` inside the
  # zip with one that adds `supported_formats = {min, max}`, rezips.
  patchMcmeta = { pname, version, src, minInclusive, maxInclusive }:
    stdenvNoCC.mkDerivation {
      inherit pname version src;
      dontUnpack = true;
      nativeBuildInputs = [ unzip zip jq ];
      buildPhase = ''
        cp "$src" pack.zip
        chmod +w pack.zip
        unzip -p pack.zip pack.mcmeta > pack.mcmeta
        jq '.pack.supported_formats = {
              "min_inclusive": ${toString minInclusive},
              "max_inclusive": ${toString maxInclusive}
            }' pack.mcmeta > pack.mcmeta.new
        mv pack.mcmeta.new pack.mcmeta
        zip pack.zip pack.mcmeta
      '';
      installPhase = ''install -m644 pack.zip "$out"'';
    };
in
[
  {
    filename = "01-stay-true-1.21.zip";
    zip = fetchurl {
      url    = "https://mediafilez.forgecdn.net/files/5493/450/Stay_True_1.21.zip";
      name   = "Stay_True_1.21.zip";
      sha256 = "0k6zx8g0yz7lfzmwpn4796y0478bypz68yd3jipki43xfmg0x9jb";
    };
  }
  {
    filename = "02-stay-true-compats-1.21.zip";
    zip = fetchurl {
      url    = "https://mediafilez.forgecdn.net/files/5966/648/staytrue1.21.zip";
      name   = "staytrue1.21.zip";
      sha256 = "0rfqghq7bwy5kl0q7x6hx36d2ac8r9w3jmp5h6007fnwb819vj2q";
    };
  }
  {
    filename = "03-fresh-animations-1.10.4.zip";
    zip = fetchurl {
      url    = "https://cdn.modrinth.com/data/50dA9Sha/versions/xN57JJts/FreshAnimations_v1.10.4.zip";
      name   = "FreshAnimations_v1.10.4.zip";
      sha256 = "1wp7inz4dd0jqzzrn617z14b1p76a427zxx4q19dkryjc2av4i4f";
    };
  }
  {
    filename = "04-create-fresh-items-1.2.0.zip";
    zip = fetchurl {
      url    = "https://cdn.modrinth.com/data/iiESLHPz/versions/5oFDoCMJ/Create_%20Fresh%20Items.zip";
      name   = "Create_Fresh_Items_1.2.0.zip";
      sha256 = "153v0drndaqn3a55a39v7bqfg6a2vf093ppwcar3hv5bfargz9ng";
    };
  }
  # FreshAnimations + Extensions (FA+) bundles every animation extension
  # into one pack. v1.9 advertises pack_format min 84 (MC 1.21.6+) and
  # misses the legacy `pack_format` key entirely — NeoForge logs a
  # `JsonParseException: No key pack_format` when it tries to parse it
  # on 1.21.1. v1.8.1 is the last release that supports 1.21.1
  # (pack_format 15 with supported_formats 15..999).
  {
    filename = "05-fa-all-extensions-1.8.1.zip";
    zip = fetchurl {
      url    = "https://cdn.modrinth.com/data/YAVTU8mK/versions/RfJ3uz2J/FA%2BAll_Extensions-v1.8.1.zip";
      name   = "FA+All_Extensions-v1.8.1.zip";
      sha256 = "05bh8g077wffdxs234zx7j9nigmjs7h0lij1yi7idd0b623da2j2";
    };
  }
  # Simply Swords Reforged: 3D weapon models for Simply Swords. The
  # upstream zip declares pack_format=16 (1.20.2) with no
  # `supported_formats`, so 1.21.1 (pack_format=34) marks it as
  # incompatible in the resource-pack screen. Content is purely model +
  # texture overrides and works on 1.21.1 unchanged — patch the mcmeta
  # at build time to advertise supported_formats=16..99.
  {
    filename = "06-simply-swords-reforged-v1.zip";
    zip = patchMcmeta {
      pname = "simply-swords-reforged";
      version = "1";
      src = fetchurl {
        url    = "https://cdn.modrinth.com/data/abPebRRB/versions/Ykvp4dCv/Simply%20Swords%20Reforged%20v1.zip";
        name   = "Simply_Swords_Reforged_v1.zip";
        sha256 = "06nfhnlpn8wpysclgwarvm5pxf1sz045bfl2k795gnf8w81vwr3f";
      };
      minInclusive = 16;
      maxInclusive = 99;
    };
  }
  # Faithful 64x — 64-pixel retexture of vanilla blocks/items, dominant
  # over Stay True 16x on every vanilla asset (numbered later wins).
  # Modded blocks fall through to Stay True Compats (02) or the mods'
  # own textures since Faithful only covers vanilla.
  {
    filename = "07-faithful-64x.zip";
    zip = fetchurl {
      url    = "https://cdn.modrinth.com/data/r4GILswZ/versions/BauEG3pq/Faithful%2064x%20-%20Release%206.zip";
      name   = "Faithful_64x_Release_6.zip";
      sha256 = "17zpqnab80yba39f2bwz0zbw2bbiw7hhvf8w0asa436gi6128a5s";
    };
  }
  # Fresh Moves — player + mob movement animation overhaul. Companion to
  # Fresh Animations (#03). "No Animated Eyes" variant is the version
  # without the eye-tracking effect since some players find it
  # uncanny-valley on creepers/villagers. pack_format 15 + a wide
  # supported_formats range covers 1.21.1.
  {
    filename = "08-fresh-moves-3.1.zip";
    zip = fetchurl {
      url    = "https://cdn.modrinth.com/data/slufHzC2/versions/lHNQh6Gv/-1.21.2%20Fresh%20Moves%20v3.1%20%28No%20Animated%20Eyes%29.zip";
      name   = "Fresh_Moves_v3.1_NoAnimatedEyes.zip";
      sha256 = "0b8zypva11jdcqm1pb27n1sgmicd8yms0wis94ywlqm4nff59hli";
    };
  }
  # Ars Nouveau Refresh — vanilla-style retexture of every Ars Nouveau
  # block + item so the mod's textures stop clashing with Stay True.
  # pack_format 34 native to 1.21.1.
  {
    filename = "09-ars-nouveau-refresh-1.2.0.zip";
    zip = fetchurl {
      url    = "https://cdn.modrinth.com/data/HuL3Q7xv/versions/ZPMAK7tA/Ars%20Nouveau%20Refresh%201.2.0.zip";
      name   = "Ars_Nouveau_Refresh_1.2.0.zip";
      sha256 = "01wgg9y7pbvd6dnqjp8awyjah9vnzrp6vbd73j8klj4rs9ssnljp";
    };
  }
  # Armory Conglomery — 3D model overhaul for vanilla + modded armor +
  # weapons. pack_format 16 with supported_formats 9..99, covers 1.21.1.
  {
    filename = "10-armory-conglomery-v2.2.zip";
    zip = fetchurl {
      url    = "https://cdn.modrinth.com/data/uJC1fwNH/versions/SBhzosuy/armory-conglomery-v2.2.zip";
      name   = "armory-conglomery-v2.2.zip";
      sha256 = "0lp5i29fka4i9cfya18ppwy549jrp4h4mw974czw467pv1ag92gy";
    };
  }
]
