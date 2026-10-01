# Shared bash-snippet generator: given a Nix list of already-built glob
# patterns (e.g. one per steamLibraryRoots entry), expands them into a
# nullglob-safe bash array of real candidate paths -- handling paths that
# contain spaces without word-splitting them. Caller still has to validate
# each candidate (e.g. check for a marker file); this only replaces the
# pattern-list -> matched-paths-array plumbing, which was previously
# copy-pasted near-verbatim between home/modules/beatsaber and modules/vr.
#
# Not used by home/modules/subnautica-vr or home/modules/helldivers2-mods:
# both build one exact literal candidate path per root rather than a glob
# pattern, so there's nothing here for them to share -- forcing them onto
# this would add nullglob/array-expansion machinery they don't need.
{ lib }:
{
  # patterns: list of glob-pattern strings (may contain shell glob chars,
  #   or none at all -- a literal path works too, just always nullglob-safe)
  # outputVar: bash array variable name to populate with matches
  # saveRestoreNullglob: true when this snippet is inlined into a longer
  #   script that keeps running after it and might rely on nullglob's prior
  #   state (e.g. home-manager activation, shared with unrelated steps);
  #   false for a standalone script/service that owns its own shell and
  #   exits right after (e.g. a systemd oneshot unit).
  expandGlobCandidates =
    {
      patterns,
      outputVar ? "candidates",
      saveRestoreNullglob ? true,
    }:
    let
      patternsBlock = lib.concatMapStringsSep "\n" (p: "  ${lib.escapeShellArg p}") patterns;
    in
    ''
      ${lib.optionalString saveRestoreNullglob ''
        __steam_glob_nullglob_state="$(shopt -p nullglob || true)"
      ''}
      shopt -s nullglob
      __steam_glob_patterns=(
      ${patternsBlock}
      )
      ${outputVar}=()
      __steam_glob_old_ifs="$IFS"
      IFS=
      for __steam_glob_pattern in "''${__steam_glob_patterns[@]}"; do
        # shellcheck disable=SC2206 # unquoted on purpose: IFS is cleared
        # above so this performs pathname expansion without word-splitting
        # the result.
        ${outputVar}+=( $__steam_glob_pattern )
      done
      IFS="$__steam_glob_old_ifs"
      ${lib.optionalString saveRestoreNullglob ''
        eval "$__steam_glob_nullglob_state"
      ''}
    '';
}
