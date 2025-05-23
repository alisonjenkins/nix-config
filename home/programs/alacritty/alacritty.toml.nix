{pkgs, ...}: ''
  [colors.bright]
  black = "#665c54"
  blue = "#83a598"
  cyan = "#8ec07c"
  green = "#b8bb26"
  magenta = "#d3869b"
  red = "#fb4934"
  white = "#fbf1c7"
  yellow = "#fabd2f"

  [colors.cursor]
  cursor = "#d5c4a1"
  text = "#282828"

  [colors.normal]
  black = "#282828"
  blue = "#83a598"
  cyan = "#8ec07c"
  green = "#b8bb26"
  magenta = "#d3869b"
  red = "#fb4934"
  white = "#d5c4a1"
  yellow = "#fabd2f"

  [colors.primary]
  background = "#282828"
  bright_foreground = "#fbf1c7"
  foreground = "#d5c4a1"

  [colors.selection]
  background = "#504945"
  text = "#d5c4a1"

  [font]
  size = 12
  [font.normal]
  family = "FiraCode Nerd Font Mono"
  style = "Regular"

  [mouse]
  hide_when_typing = true

  [terminal]
  osc52 = "CopyPaste"

  [terminal.shell]
  args = ["-l", "-c", "tmux attach ; tmux", "-l", "-c", "tmux attach ; tmux"]
  program = "${pkgs.zsh}/bin/zsh"

  [window]
  decorations = "None"
  opacity = 0.9

  [window.padding]
  x = 12
  y = 12
''
