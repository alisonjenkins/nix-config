{ pkgs, ... }:

# Backup helper for `home-manager.backupCommand`.
#
# home-manager runs the configured command *unquoted*:
#
#     run $HOME_MANAGER_BACKUP_COMMAND "$targetPath"
#
# (modules/files.nix, linkGeneration). The variable is word-split into argv
# and the target is appended as the final argument — it is never evaluated by
# a shell. An inline snippet like `mv -v "$1" "$1.backup-$(date ...)"` is
# therefore passed to `mv` as the literal words `"$1"`, `"$1.backup-$(date`
# and `+%Y%m%d-%H%M%S)"`, which is where the
#
#     mv: cannot stat '"$1"'
#
# activation errors come from. Nothing gets backed up, and the following
# `ln -Tsf ... || exit 1` then aborts activation outright whenever the target
# is a directory that should have been moved aside.
#
# So the command has to be a single argv[0] — one executable that takes the
# target as $1. That is this script.
pkgs.writeShellApplication {
  name = "hm-backup-file";

  runtimeInputs = [ pkgs.coreutils ];

  text = ''
    if [ "$#" -ne 1 ]; then
      echo "usage: hm-backup-file <path>" >&2
      exit 2
    fi

    target="$1"

    # home-manager only calls us for paths it found in the way, but the check
    # and the move are not atomic — treat a vanished target as success.
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      exit 0
    fi

    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    backup="$target.backup-$stamp"

    # Second-resolution stamps collide when one activation backs up several
    # files, so keep counting up rather than clobbering an earlier backup.
    n=0
    while [ -e "$backup" ] || [ -L "$backup" ]; do
      n=$((n + 1))
      backup="$target.backup-$stamp-$n"
    done

    mv -v -- "$target" "$backup"
  '';

  meta = {
    description = "Move a file or directory aside during home-manager activation";
    mainProgram = "hm-backup-file";
  };
}
