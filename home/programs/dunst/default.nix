{ ... }: {
  home.file.".config/dunst/dunstrc".text = ''
    [global]
        rounded = yes
        monitor = 0
        follow = mouse
        width = 400
        height = 400
        origin = top-right
        offset = 15x15
        scale = 0
        progress_bar = false
        indicate_hidden = yes
        transparency = 0
        separator_height = 2
        padding = 10
        horizontal_padding = 10
        text_icon_padding = 0
        frame_width = 1
        frame_color = "#232323"
        gap_size = 0
        separator_color = frame
        sort = yes
        idle_threshold = 120
        font = Source Sans Pro 10
        line_height = 0
        markup = full
        format = "<span foreground='#f3f4f5'><b>%s %p</b></span>\n%b"
        alignment = left
        vertical_alignment = center
        show_age_threshold = 60
        ellipsize = middle
        ignore_newline = no
        stack_duplicates = true
        hide_duplicate_count = false
        show_indicators = yes
        icon_position = left
        min_icon_size = 0
        max_icon_size = 32
        icon_path = /usr/share/icons/Paper/16x16/status/:/usr/share/icons/Paper/16x16/devices/:/usr/share/icons/Paper/16x16/apps/
        sticky_history = yes
        history_length = 20
        always_run_script = true
        corner_radius = 10
        ignore_dbusclose = false
        force_xinerama = false
        mouse_left_click = do_action, close_current
        mouse_middle_click = close_current
        mouse_right_click = close_all
        notification_limit = 5

        browser = /usr/bin/env librewolf -new-tab

    [urgency_low]
        background = "#232323"
        foreground = "#2596be"
        timeout = 10

    [urgency_normal]
        background = "#1e1e2a"
        foreground = "#2596be"
        timeout = 10

    [urgency_critical]
        background = "#d64e4e"
        foreground = "#f0e0e0"
        frame_color = "#d64e4e"
        timeout = 0
        default_icon = /usr/share/icons/Paper/16x16/status/dialog-warning.png

  '';
}
