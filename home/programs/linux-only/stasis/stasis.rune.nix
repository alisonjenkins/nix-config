{
  bluetoothHeadsetMac ? "",
  idleLockGracePeriodSeconds ? 30,
  lockFadeInSeconds ? 1,
  lockGracePeriodSeconds ? 0,
  pkgs,
}: ''
  @author "Alison Jenkins"
  @description "Stasis configuration file"

  # https://saltnpepper97.github.io/stasis/configuration
  stasis:
    debounce_seconds 4
    ignore_remote_media true
    lid_close_action "suspend"
    lid_open_action "wake"
    monitor_media true
    pre_suspend_command "${pkgs.suspendScripts}/bin/suspend-pre"
    respect_idle_inhibitors true
    resume_command "${pkgs.suspendScripts}/bin/suspend-resume '${bluetoothHeadsetMac}'"

    inhibit_apps [
      "mpv"
      r".*[Vv]ideo.*"
      r".*\.exe"
      r"^chrome.*"
      r"firefox.*"
      r"steam_app_.*"
    ]

    dpms:
      timeout = 330
      command "niri msg action power-off-monitors"
      resume_command "niri msg action power-on-monitors"
    end

    lock_screen:
      command "${pkgs.lock-session}/bin/lock-session ${toString lockGracePeriodSeconds} ${toString lockFadeInSeconds}"
      lock_command "${pkgs.lock-session}/bin/lock-session ${toString idleLockGracePeriodSeconds} ${toString lockFadeInSeconds}"
      resume-command "notify-send 'Welcome Back $env.USER!'"
      timeout = 900
    end
  end
''
