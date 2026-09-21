{ config, lib, pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    ../../programs/linux-only/steam-command-runner
    ../../programs/linux-only/sunshine-wrappers
    ../../programs/linux-only/steam-stream-mode
    ../../programs/linux-only/uhk-keymaps
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;
  modules.subnauticaVR = {
    enable = true;
    # Subnautica lives on the secondary Steam library on this host, not the
    # module's ~/.local/share/Steam default — confirmed via appmanifest_264710.acf
    # and the steam-command-runner shim log showing the real launched exe path.
    steamLibraryPath = "/media/steam-games-1/SteamLibrary";
  };
  modules.beatsaber.enable = true;

  # Remote Play captures a whole output and Steam only ever asks the portal
  # for monitors, so on the 5120x1440 ultrawide a Deck received about 1280x360
  # of content inside its 800-line frame, showing whatever was on screen. The
  # niri virtual output declared in custom.niri.virtualOutputs is turned on and
  # resized for the client, and the game is moved onto it, leaving DP-2 alone.
  custom.steamStreamMode = {
    enable = true;
    # niriPackage is set from the host config, where the patched package the
    # session actually runs is in scope — `niri msg` has to match the running
    # compositor, and virtual output support is a patch rather than upstream.
    # Taken from the output's own declaration so the watcher cannot resize it
    # to a shape the output was not declared with.
    defaultWidth = config.custom.niri.virtualOutputs.steam.width;
    defaultHeight = config.custom.niri.virtualOutputs.steam.height;
    refresh = config.custom.niri.virtualOutputs.steam.refresh;
  };

  home.packages = [
    pkgs.nbt-studio
    # Provides uhk-switch-keymap, used by the pre_launch/post_exit hooks
    # below. The gamescope shim below is symlinked separately by name
    # rather than exposed via this package, so this doesn't duplicate it.
    inputs.steam-command-runner.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # obs-gamecapture LD_PRELOADs obs-vkcapture's Vulkan/GL hook so OBS's Game
  # Capture source can find any game launched through steam-command-runner,
  # without adding it per-game as a Steam launch option.
  programs.steamCommandRunner = {
    enable = true;
    preCommand = "obs-gamecapture gamemoderun";
    defaultProton = "DW-Proton Latest";
    shimDebug = true;
    innerEnv.MANGOHUD = "1";
    gamescopeArgs = "-w 2540 -h 1440 -W 2540 -H 1440 -b --rt --hdr-enabled --hdr-debug-force-support --force-grab-cursor -F fsr -r 120";
    # Almost every launch here goes through gamescope, so the module default
    # of skipping preCommand under gamescope would silently drop the
    # obs-gamecapture wrap for nearly all games.
    gamescopeSkipPreCommand = false;

    # Follows the active game with the matching UHK keymap: HD2's stratagem
    # macros while it's running, back to the daily-driver QWERTY keymap on
    # exit. uhk-switch-keymap auto-discovers the connected UHK, so this
    # doesn't need a device id.
    games."553850" = {
      hooks.pre_launch.command = "uhk-switch-keymap HD2";
      hooks.post_exit.command = "uhk-switch-keymap QWR";
    };

    # Subnautica (264710): syncs the subnautica-vr-mods payload (see
    # modules.subnauticaVR above) before every launch. hooks.pre_launch
    # waits for the sync to finish (steam-command-runner's own `wait = true`
    # default) before continuing — not for it to succeed; a failed hook is
    # logged and the launch proceeds regardless, so a sync failure needs
    # checking for in the runner's own log, not assumed caught here.
    # gamescope_enabled = false: hooks only fire via the gamescope-shim
    # launch path (src/shim/gamescope.rs), which always execs the real
    # gamescope binary once Steam's routed the launch through it —
    # gamescope_enabled only gates whether the configured gamescopeArgs
    # (HD2's ultrawide/HDR/FSR tuning) get applied, not whether gamescope
    # runs at all. So this still wraps Subnautica in a bare, argument-less
    # gamescope rather than skipping it — harmless here, since SteamVR's own
    # OpenVR compositor renders straight to the headset, bypassing gamescope
    # entirely; gamescope only ever sees the flatscreen mirror window.
    games."264710" = {
      gamescope_enabled = false;
      hooks.pre_launch.command = "subnautica-vr-mod-sync";
      # SubmersedVR checks the active XR runtime at startup and refuses to
      # initialize (silently, past a log line) on anything it doesn't
      # recognize as SteamVR — a Quest 2 heads on this as an Oculus runtime
      # without this flag, per upstream's README. Confirmed live: BepInEx's
      # own log showed "SubmersedVR only supports SteamVR!" until this was
      # added.
      game_args = "-vrmode openvr";
      # subnautica-vr-mod-sync's own WINEDLLOVERRIDES export only applies
      # when it execs the game itself; a pre_launch hook doesn't exec
      # anything, so the override has to be set here instead. Composed
      # from the global env the same way the script composes its own
      # runtime WINEDLLOVERRIDES, so a global override set above isn't
      # silently clobbered by this per-game one.
      env.WINEDLLOVERRIDES =
        let
          globalOverride = config.programs.steamCommandRunner.env.WINEDLLOVERRIDES or "";
        in
        "winhttp=n,b" + lib.optionalString (globalOverride != "") ";${globalOverride}";
    };
  };

  programs.uhkKeymaps.enable = true;

  # The module above writes the runner's config; this puts the runner itself
  # where Steam's launch chain will find it. It intercepts `gamescope` to
  # apply per-game arguments while keeping the Steam overlay and stop button
  # working, and only does so under the name `gamescope` from ~/.local/bin,
  # which precedes the system profile in PATH — installing it via
  # home.packages would expose it under its own name and never be reached.
  # Previously a symlink to a debug build inside a working tree, so every
  # game's launch chain depended on an unpinned binary.
  home.file.".local/bin/gamescope".source =
    "${inputs.steam-command-runner.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/steam-command-runner";
}
