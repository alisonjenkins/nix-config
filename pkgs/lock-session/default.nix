{
  writeShellScriptBin,
  procps,
  swaylock-effects,
  ...
}:
writeShellScriptBin "lock-session" ''
  #!/bin/bash
  GRACE_SECONDS="''${1:-}"

  SWAYLOCK_ARGS=(
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

  ${procps}/bin/pidof swaylock || ${swaylock-effects}/bin/swaylock ''${SWAYLOCK_ARGS[@]}
''
