# Alternate HRTF datasets for positional-audio-bench's sweep-datasets, beyond
# the MIT KEMAR set bundled in pkgs.libmysofa.
#
# CIPIC (UC Davis) is the only one of the four candidates evaluated
# (CIPIC/SADIE II/ARI/HUTUBS) with an unambiguous redistribution grant: "The
# Regents of the University of California hereby grant users permission to
# reproduce and/or use materials available therein for any purpose —
# educational, research or commercial" (no share-alike/attribution-chain
# terms to worry about in a binary cache). Files mirrored as individual SOFA
# measurements at sofacoustics.org since the original UC Davis host is gone.
#
# Subjects 021 and 165 are documented CIPIC mannequin variants — the same
# KEMAR measurement methodology as the bundled default, but with deliberately
# small and large pinnae respectively. That makes them a clean three-point
# comparison against modules/desktop/default.nix's default
# MIT_KEMAR_normal_pinna.sofa: same head, three pinna sizes.
{ fetchurl }:
{
  cipic-021-small-pinna = fetchurl {
    url = "https://sofacoustics.org/data/database/cipic/subject_021.sofa";
    hash = "sha256-ZowjJW4PBeW/s4CuF9jFeVV1hD8KCKFffQQueNVjPgQ=";
  };

  cipic-165-large-pinna = fetchurl {
    url = "https://sofacoustics.org/data/database/cipic/subject_165.sofa";
    hash = "sha256-yMoGnQqfQBqkrJfzSTMRa/Wo40K3a7/DOGcE/SIcP7c=";
  };
}
