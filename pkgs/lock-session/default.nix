{
  writeShellApplication,
  procps,
  swaylock-effects,
  ...
}:
writeShellApplication {
  name = "lock-session";
  runtimeInputs = [ procps swaylock-effects ];
  text = ''
    GRACE_SECONDS="''${1:-}"
    FADE_IN_SECONDS="''${2:-}"

    # swayidle's unit has only bash on PATH, so look in the profile dirs that
    # carry noctalia (home-manager profile, per-user NixOS profile, system).
    PATH="$PATH:''${HOME:-}/.nix-profile/bin:/etc/profiles/per-user/''${USER:-}/bin:/run/current-system/sw/bin"

    # noctalia owns the lock when its shell is running. Its grace period is
    # lockscreen.grace_period_seconds in its config, so the arguments below
    # only apply to the swaylock fallback (Plasma sessions, noctalia down).
    if ! command -v noctalia >/dev/null; then
      echo "event=lock locker=swaylock reason=noctalia_not_found" >&2
    elif noctalia msg session lock; then
      echo "event=lock locker=noctalia" >&2
      exit 0
    else
      echo "event=lock locker=swaylock reason=noctalia_msg_failed" >&2
    fi

    SWAYLOCK_ARGS=(
      "--color"
      "050505"
      "--clock"
      "--daemonize"
      "--effect-blur"
      "5x4"
      "--indicator-idle-visible"
      "--screenshots"
    )

    if [[ "$GRACE_SECONDS" ]]; then
      SWAYLOCK_ARGS+=("--grace")
      SWAYLOCK_ARGS+=("$GRACE_SECONDS")
      SWAYLOCK_ARGS+=("--grace-no-mouse")
      SWAYLOCK_ARGS+=("--grace-no-touch")
    fi

    if [[ "$FADE_IN_SECONDS" ]]; then
      SWAYLOCK_ARGS+=("--fade-in")
      SWAYLOCK_ARGS+=("$FADE_IN_SECONDS")
    fi

    pidof swaylock || swaylock "''${SWAYLOCK_ARGS[@]}"
  '';
}
