{
  writeShellScriptBin,
  procps,
  swaylock-effects,
  ...
}:
writeShellScriptBin "lock-session" ''
  #!/bin/bash
  GRACE_SECONDS="''${1:-}"
  FADE_IN_SECONDS="''${2:-}"

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

  ${procps}/bin/pidof swaylock || ${swaylock-effects}/bin/swaylock ''${SWAYLOCK_ARGS[@]}
''
