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

  disabled = [ ];
}
