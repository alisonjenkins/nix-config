{
  writeShellScriptBin,
  procps,
  swaylock-effects,
  ...
}:
writeShellScriptBin "lock-session" ''
#!/bin/sh
${procps}/bin/pidof swaylock || ${swaylock-effects}/bin/swaylock \
  --clock \
  --daemonize \
  --effect-blur 5x4 \
  --grace 5 \
  --grace-no-mouse \
  --grace-no-touch \
  --indicator-idle-visible \
  --screenshots
''
