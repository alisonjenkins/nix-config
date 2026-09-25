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
  # 16 GiB RX 9070 XT: one model at a time, loaded on demand. A q8_0 KV
  # cache doubles each context for the VRAM f16 took, at the same speed
  # (measured 2026-09-25, VRAM total / shared memory / generation):
  #   small,   16k f16: 9.6 GiB / 512 MiB / 85 tok/s; 32k q8_0: 9.8 GiB / 544 MiB / 81 tok/s
  #   quality,  8k f16: 15.9 GiB / 499 MiB / 34 tok/s; 16k q8_0: 16.0 GiB / 516 MiB / 34 tok/s
  #   quality, 24k q8_0 fits with 54 MiB spare; 32k spills to system RAM
  #   (shared 1.2 GiB) and drops to 23 tok/s.
  #   fast,    32k q8_0: 14.7 GiB / 278 MiB / 127 tok/s
  # fast is a mixture-of-experts model: 35B parameters, 3B used per token,
  # so it runs faster than small and did better on every task it was given
  # (home/skills/delegation/delegate-to-local.md). small stays because it
  # is the one that fits beside a game.
  # vramMiB is each profile's own use, rounded up to 100 MiB: its total less
  # the ~1.1 GiB the desktop uses. Quality measured 14,910 MiB and fast
  # 13,868 MiB (sysfs mem_info_vram_used, loaded and after a request, less
  # the idle desktop's ~1,140 MiB, 2026-09-25). The switch fit check's
  # estimate put them at 16.7 and 15.8 GiB and refused both on an idle
  # desktop. The check adds no margin to a measured value, and an idle
  # desktop leaves about 15,170 MiB free, so both only load with nothing
  # else on the GPU.
  modules.delegateToLocal.profiles = let
    q8Cache = [ "--flash-attn" "on" "--cache-type-k" "q8_0" "--cache-type-v" "q8_0" ];
  in {
    fast = {
      model = pkgs.llama-models.qwen3-6-35b-a3b-ud-iq3-s.modelFile;
      launchArgs = [ "--gpu-layers" "999" "--ctx-size" "32768" "--jinja" ] ++ q8Cache;
      vramMiB = 13900;
      description = "Qwen3.6-35B-A3B UD-IQ3_S (MoE), ~12.7 GiB, 127 tok/s: new files, edits and review fixes from a spec";
    };
    small = {
      model = pkgs.llama-models.qwen3-8b-q6-k.modelFile;
      launchArgs = [ "--gpu-layers" "999" "--ctx-size" "32768" "--jinja" ] ++ q8Cache;
      vramMiB = 9000;
      description = "Qwen3-8B Q6_K, ~6.3 GiB: extraction only; fits beside a game";
    };
    quality = {
      model = pkgs.llama-models.qwen3-6-27b-ud-q3-k-xl.modelFile;
      launchArgs = [ "--gpu-layers" "999" "--ctx-size" "16384" "--jinja" ] ++ q8Cache;
      vramMiB = 15000;
      # Thinking mode stays on, so replies are long: 34 tok/s on a free
      # GPU (2026-09-25), but agent tasks took 79 to 264 s. The 3.7 tok/s
      # measured 2026-09-22 was probably with the GPU shared.
      description = "Qwen3.6-27B UD-Q3_K_XL, ~13.5 GiB: reading code, harder reasoning; thinking on, so replies take a minute or more";
    };
  };
  modules.subnauticaVR = {
    enable = true;
    # Subnautica lives on the secondary Steam library on this host, not the
    # module's ~/.local/share/Steam default — confirmed via appmanifest_264710.acf
    # and the steam-command-runner shim log showing the real launched exe path.
    steamLibraryPath = "/media/steam-games-1/SteamLibrary";
  };
  modules.beatsaber = {
    enable = true;
    # Beat Saber (appid 620980) lives in the secondary library folder, not
    # the default ~/.local/share/Steam (that one holds a different library,
    # see modules.vr.steamLibraryRoots below -- two libraries on the same
    # drive). Overrides the module default entirely, so list both.
    steamLibraryRoots = [
      "${config.home.homeDirectory}/.local/share/Steam"
      "/media/steam-games-1/SteamLibrary"
    ];
  };

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
    # The MacBook streams to headphones; everything else gets a plain
    # downmix until its speakers or headphones are known.
    audio.clients."ali-mba" = "binaural";
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
      # HD2's Stingray engine takes no resolution argument, so a streamed
      # launch rewrites its saved resolution to the client's for the run and
      # puts it back on exit (runner ADR 0011).
      stream_resolution_rules = [{
        file = "{prefix}/drive_c/users/steamuser/AppData/Roaming/Arrowhead/Helldivers2/user_settings.config";
        pattern = "(?m)^(\\s*(?:screen|render)_resolution = \\[\\s*)\\d+(\\s+)\\d+";
        replacement = "\${1}{width}\${2}{height}";
      }];
    };

    # Forza Horizon 6: ForzaTech takes no resolution argument either, and
    # left at its saved 1024x768 it drew a small corner of the streamed
    # output. Same rewrite-and-restore as HD2, on its UserConfigSelections.
    games."2483190".stream_resolution_rules = [{
      file = "{prefix}/drive_c/users/steamuser/AppData/Local/ForzaHorizon6/LocalStorage_Shared/ForzaUserConfigSelections/UserConfigSelections";
      pattern = "(<ResolutionWidth value=\")\\d+(\"/>\\s*<ResolutionHeight value=\")\\d+";
      replacement = "\${1}{width}\${2}{height}";
    }];

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
