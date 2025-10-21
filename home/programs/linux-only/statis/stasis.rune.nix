{
  bluetoothHeadsetMac ? "",
  idleLockGracePeriodSeconds ? 30,
  lockFadeInSeconds ? 1,
  lockGracePeriodSeconds ? 0,
  pkgs,
}: ''
  # https://github.com/saltnpepper97/stasis/wiki/Configuration
  idle:
    debounce_seconds 4                              # ✅ Now configurable (optional, default is 3)
    ignore_remote_media                             # ✅ This stops KDEConnect and other apps who play connected media from triggering timer pauses
    monitor_media true
    pre_suspend_command "${pkgs.suspendScripts}/bin/suspend-pre"
    respect_idle_inhibitors true
    resume_command "${pkgs.suspendScripts}/bin/suspend-resume '${bluetoothHeadsetMac}'"

    inhibit_apps [
      "mpv"
      r".*[Vv]ideo.*"
      r".*\.exe",
      r"^chrome.*"
      r"firefox.*"
      r"steam_app_.*",
    ]

    lock_screen:
      command "${pkgs.lock-session}/bin/lock-session ${toString lockGracePeriodSeconds} ${toString lockFadeInSeconds}"
      lock_command "${pkgs.lock-session}/bin/lock-session ${toString idleLockGracePeriodSeconds} ${toString lockFadeInSeconds}" # ✅ Required for lock detection
      resume_command "notify-send 'Welcome back!'"         # ✅ Per-action resume
      timeout = 900
    end

    dpms:
      timeout = 330
      command "niri msg action power-off-monitors"
      resume_command "niri msg action power-on-monitors"  # ✅ Per-action resume
    end
  end
''
