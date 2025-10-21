{inputs}:''
  [Unit]
  Description=Stasis Wayland Idle Manager
  After=graphical-session.target
  Wants=graphical-session.target

  [Service]
  Type=simple
  ExecStart=${inputs.stasis}/bin/stasis
  Restart=always
  RestartSec=5
  Environment=WAYLAND_DISPLAY=wayland-0

  # Optional: wait until WAYLAND_DISPLAY exists
  ExecStartPre=/bin/sh -c 'while [ ! -e /run/user/%U/wayland-0 ]; do sleep 0.1; done'

  [Install]
  WantedBy=default.target
''
