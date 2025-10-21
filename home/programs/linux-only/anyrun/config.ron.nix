''
Config(
  // Position/size fields use an enum for the value, it can be either:
  // Absolute(n): The absolute value in pixels
  // Fraction(n): A fraction of the width or height of the full screen (depends on exclusive zones and the settings related to them) window respectively

  // The horizontal position, adjusted so that Relative(0.5) always centers the runner
  x: Fraction(0.5),

  // The vertical position, works the same as `x`
  y: Fraction(0.4),

  // The width of the runner
  width: Absolute(800),

  // The minimum height of the runner, the runner will expand to fit all the entries
  // NOTE: If this is set to 0, the window will never shrink after being expanded
  height: Absolute(60),

  // Hide match and plugin info icons
  hide_icons: false,

  // ignore exclusive zones, f.e. Waybar
  ignore_exclusive_zones: false,

  // Layer shell layer: Background, Bottom, Top, Overlay
  layer: Overlay,

  // Hide the plugin info panel
  hide_plugin_info: false,

  // Close window when a click outside the main box is received
  close_on_click: true,

  // Show search results immediately when Anyrun starts
  show_results_immediately: true,

  // Limit amount of entries shown in total
  max_entries: None,

  // List of plugins to be loaded by default, can be specified with a relative path to be loaded from the
  // `<anyrun config dir>/plugins` directory or with an absolute path to just load the file the path points to.
  //
  // The order of plugins here specifies the order in which they appear
  // in the results. As in it works as a priority for the plugins.
  plugins: [
    "libapplications.so",
    "libsymbols.so",
    "libshell.so",
    "libtranslate.so",
  ],

  keybinds: [
    Keybind(
      key: "Return",
      action: Select,
    ),
    Keybind(
      key: "Up",
      action: Up,
    ),
    Keybind(
      key: "Down",
      action: Down,
    ),
    Keybind(
      key: "ISO_Left_Tab",
      action: Up,
      shift: true,
    ),
    Keybind(
      key: "Tab",
      action: Down,
    ),
    Keybind(
      key: "Escape",
      action: Close,
    ),
  ],
)
''
