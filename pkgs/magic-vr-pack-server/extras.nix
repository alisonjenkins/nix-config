# Hand-kept exceptions to the generated mods.nix.
#
# omitted:  asked for but never put in modlist.toml. Documentation only.
# disabled: resolved into mods.nix but kept out of server and client,
#           matched by slug. Each entry says why, so a later bump can retry.
{
  omitted = [
    {
      slug = "idas";
      reason = "Integrated Dungeons and Structures 1.21.1 NeoForge hard-requires Create, Quark and Supplementaries; Create is excluded from this pack.";
    }
  ];

  disabled = [
    {
      slug = "chunky";
      reason = "Chunky 1.4.23 + Distant Horizons 3.3.3 crash the first world creation: DH's Chunky hook calls ChunkyProvider.get() during spawn-chunk generation, before Chunky has loaded (IllegalStateException: Chunky is not loaded). DH's own distant generation covers pre-generation.";
    }
    {
      slug = "unlimitedperipheralworks";
      reason = "UnlimitedPeripheralWorks (alpha) crashes the server tick loop once the world is up: its apprentice_magic_tome pocket upgrade rejects Ars Nouveau's apprentice_spell_book (IllegalArgumentException in CC:Tweaked UpgradeData). Advanced Peripherals and Tom's Peripherals stay.";
    }
  ];
}
