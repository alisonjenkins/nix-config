# Set tide variables before the prompt loads
set -g tide_cmd_duration_threshold 3000

# Rainbow style configuration
set -g tide_color_mode 'True color'
set -g tide_prompt_style 'Two lines, character'
set -g tide_prompt_char_icon '❯'
set -g tide_prompt_char_vi_icon_default '❯'
set -g tide_prompt_char_vi_icon_replace '▶'
set -g tide_prompt_char_vi_icon_visual 'V'

# Colors and appearance
set -g tide_character_color 5FD700
set -g tide_character_color_failure FF0000

# Left prompt items
set -g tide_left_prompt_items pwd git

# Right prompt items
set -g tide_right_prompt_items status cmd_duration context jobs time

# Prompt connection and spacing
set -g tide_prompt_add_newline_before true
set -g tide_prompt_connection ' '
set -g tide_prompt_connection_color 6C6C6C
set -g tide_prompt_connection_icon '··········'
set -g tide_prompt_color_frame_and_connection 6C6C6C
set -g tide_left_prompt_frame_enabled false
set -g tide_right_prompt_frame_enabled false
set -g tide_left_prompt_separator_diff_color '⮀'
set -g tide_left_prompt_separator_same_color '⮁'
set -g tide_right_prompt_separator_diff_color '⮂'
set -g tide_right_prompt_separator_same_color '⮃'

# Rainbow separators (angled)
set -g tide_left_prompt_prefix ""
set -g tide_left_prompt_suffix '⮀'
set -g tide_right_prompt_prefix '⮂'
set -g tide_right_prompt_suffix ""

# Time format (24-hour)
set -g tide_time_format '%H:%M'

# PWD settings
set -g tide_pwd_icon '󰉋'
set -g tide_pwd_icon_home '󰋜'
set -g tide_pwd_icon_unwritable '󰉐'
set -g tide_pwd_color_anchors 00AFFF
set -g tide_pwd_color_dirs 0087AF
set -g tide_pwd_color_truncated_dirs 8787AF

# Git settings
set -g tide_git_icon ''
set -g tide_git_color_branch 5FD700
set -g tide_git_color_operation FF0000
set -g tide_git_color_upstream 5FD700
set -g tide_git_color_stash 5FD700
set -g tide_git_color_conflicted FF0000
set -g tide_git_color_dirty D7AF00
set -g tide_git_color_staged D7AF00
set -g tide_git_color_stashed 5FD700
set -g tide_git_color_untracked 00AFFF
set -g tide_git_truncation_length 24

# Status
set -g tide_status_icon '✔'
set -g tide_status_icon_failure '✘'

# Cmd duration
set -g tide_cmd_duration_icon '󰔛'
set -g tide_cmd_duration_color 87875F

# Context
set -g tide_context_always_display false
set -g tide_context_color_default D7AF87
set -g tide_context_color_root D7AF00
set -g tide_context_color_ssh D7AF87

# Jobs
set -g tide_jobs_icon '󰜎'

# Time
set -g tide_time_color 5F8787
set -g tide_time_icon '󰥔'

# Transient prompt (disabled)
set -g tide_prompt_transient_enabled false
