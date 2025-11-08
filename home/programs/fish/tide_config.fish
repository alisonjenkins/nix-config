# Tide prompt configuration
# Auto-generated from: tide configure --auto --style=Rainbow --prompt_colors='True color' 
# --show_time='24-hour format' --rainbow_prompt_separators=Angled --powerline_prompt_heads=Sharp 
# --powerline_prompt_tails=Flat --powerline_prompt_style='Two lines, character and frame' 
# --prompt_connection=Dotted --powerline_right_prompt_frame=No 
# --prompt_connection_andor_frame_color=Dark --prompt_spacing=Sparse --icons='Many icons' --transient=No

# Character settings
set -g tide_character_color 5FD700
set -g tide_character_color_failure FF0000
set -g tide_character_icon \u276f
set -g tide_character_vi_icon_default \u276e
set -g tide_character_vi_icon_replace \u25b6
set -g tide_character_vi_icon_visual V

# Prompt layout
set -g tide_left_prompt_frame_enabled true
set -g tide_left_prompt_items os pwd git newline character
set -g tide_right_prompt_frame_enabled false
set -g tide_right_prompt_items status cmd_duration context jobs direnv bun node python rustc java php pulumi ruby go gcloud kubectl distrobox toolbox terraform aws nix_shell crystal elixir zig time

# Prompt spacing and connection
set -g tide_prompt_add_newline_before true
set -g tide_prompt_color_frame_and_connection 585858
set -g tide_prompt_color_separator_same_color 949494
set -g tide_prompt_icon_connection \u00b7
set -g tide_prompt_min_cols 34
set -g tide_prompt_pad_items true
set -g tide_prompt_transient_enabled false

# Left prompt separators (Angled)
set -g tide_left_prompt_prefix 
set -g tide_left_prompt_separator_diff_color \ue0b0
set -g tide_left_prompt_separator_same_color \ue0b1
set -g tide_left_prompt_suffix \ue0b0

# Right prompt separators (Angled)
set -g tide_right_prompt_prefix \ue0b2
set -g tide_right_prompt_separator_diff_color \ue0b2
set -g tide_right_prompt_separator_same_color \ue0b3
set -g tide_right_prompt_suffix 

# OS item
set -g tide_os_bg_color 5277C3
set -g tide_os_color FFFFFF
set -g tide_os_icon \uf313

# PWD settings
set -g tide_pwd_bg_color 3465A4
set -g tide_pwd_color_anchors E4E4E4
set -g tide_pwd_color_dirs E4E4E4
set -g tide_pwd_color_truncated_dirs BCBCBC
set -g tide_pwd_icon \uf07c
set -g tide_pwd_icon_home \uf015
set -g tide_pwd_icon_unwritable \uf023
set -g tide_pwd_markers .bzr .citc .git .hg .node-version .python-version .ruby-version .shorten_folder_marker .svn .terraform bun.lockb Cargo.toml composer.json CVS go.mod package.json build.zig

# Git settings
set -g tide_git_bg_color 4E9A06
set -g tide_git_bg_color_unstable C4A000
set -g tide_git_bg_color_urgent CC0000
set -g tide_git_color_branch 000000
set -g tide_git_color_conflicted 000000
set -g tide_git_color_dirty 000000
set -g tide_git_color_operation 000000
set -g tide_git_color_staged 000000
set -g tide_git_color_stash 000000
set -g tide_git_color_untracked 000000
set -g tide_git_color_upstream 000000
set -g tide_git_icon \uf1d3
set -g tide_git_truncation_length 24
set -g tide_git_truncation_strategy ''

# Status settings
set -g tide_status_bg_color 2E3436
set -g tide_status_bg_color_failure CC0000
set -g tide_status_color 4E9A06
set -g tide_status_color_failure FFFF00
set -g tide_status_icon \u2714
set -g tide_status_icon_failure \u2718

# CMD duration settings
set -g tide_cmd_duration_bg_color C4A000
set -g tide_cmd_duration_color 000000
set -g tide_cmd_duration_decimals 0
set -g tide_cmd_duration_icon \uf252
set -g tide_cmd_duration_threshold 3000

# Time settings
set -g tide_time_bg_color D3D7CF
set -g tide_time_color 000000
set -g tide_time_format %T

# Context settings
set -g tide_context_always_display false
set -g tide_context_bg_color 444444
set -g tide_context_color_default D7AF87
set -g tide_context_color_root D7AF00
set -g tide_context_color_ssh D7AF87
set -g tide_context_hostname_parts 1

# Jobs settings
set -g tide_jobs_bg_color 444444
set -g tide_jobs_color 4E9A06
set -g tide_jobs_icon \uf013
set -g tide_jobs_number_threshold 1000

# Direnv settings
set -g tide_direnv_bg_color D7AF00
set -g tide_direnv_bg_color_denied FF0000
set -g tide_direnv_color 000000
set -g tide_direnv_color_denied 000000
set -g tide_direnv_icon \u25bc

# Language/tool version indicators
set -g tide_aws_bg_color FF9900
set -g tide_aws_color 232F3E
set -g tide_aws_icon \uf270

set -g tide_go_bg_color 00ACD7
set -g tide_go_color 000000
set -g tide_go_icon \ue627

set -g tide_java_bg_color ED8B00
set -g tide_java_color 000000
set -g tide_java_icon \ue256

set -g tide_kubectl_bg_color 326CE5
set -g tide_kubectl_color 000000
set -g tide_kubectl_icon \U000f10fe

set -g tide_nix_shell_bg_color 7EBAE4
set -g tide_nix_shell_color 000000
set -g tide_nix_shell_icon \uf313

set -g tide_rustc_bg_color F74C00
set -g tide_rustc_color 000000
set -g tide_rustc_icon \ue7a8

set -g tide_terraform_bg_color 800080
set -g tide_terraform_color 000000
set -g tide_terraform_icon \U000f1062
