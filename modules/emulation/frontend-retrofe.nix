# modules/emulation/frontend-retrofe.nix
#
# RetroFE frontend wiring (frontend = "retrofe"). See design/05-frontend.md.
#
# RetroFE is a native SDL2/GStreamer frontend (pkgs.retrofe 0.10.31). It reads
# its whole config tree from $RETROFE_PATH (falling back to CWD). The store
# binary + its bundled example tree ($out/share/retrofe/example, which carries
# the default layouts) are READ-ONLY, but RetroFE writes runtime state (logs,
# meta cache) back into RETROFE_PATH. So we:
#
#   1. Build the complete config tree as a store derivation (`retrofeConfig`):
#      seed it from the package's example tree (for the default layouts), then
#      overlay our generated settings / collections / launchers / per-game
#      override confs / optional themes.
#   2. Ship a wrapper (`retrofe-emulation`) that copies that store tree into a
#      writable, persisted dir (~/.local/share/retrofe), makes it writable,
#      sets RETROFE_PATH, and execs the real binary there. Re-copying on every
#      launch means the managed (declarative) files always reset to the Nix
#      state, while RetroFE's own runtime files (meta cache, log) survive
#      between launches. ROMs/media never enter this tree — collection
#      `list.path` points straight at the B2-synced ~/Emulation/roms/<dir>.
#
# CONFIG MODEL (verified against RetroFE docs / source, 2026-06-01):
#   $RETROFE_PATH/
#     settings.conf                         global (layout=, fullscreen=, ...)
#     collections/Main/menu.txt             one line per collection shown
#     collections/<plat>/settings.conf      list.extensions=, list.path=, launcher=
#     collections/<plat>/launchers/<rom>.conf   per-GAME launcher override
#                                               (one line: the launcher name;
#                                                <rom> = ROM basename w/o ext,
#                                                CASE-SENSITIVE)
#     launchers/<name>.conf                 executable= / arguments= (per backend)
#       arguments tokens: %ITEM_FILEPATH% (full path), %ITEM_NAME% (basename, no ext)
#
# Collections + launchers are DERIVED from the per-platform model
# (default.nix + catalogue.nix): one collection per ENABLED platform, one
# launcher per (platform, backend) it installs, the collection default launcher
# = the platform's primary (first `emulators`) backend, and a per-game override
# conf for any `{ file; emulator; }` entry that picks a non-primary backend.
#
# UNVERIFIED-ON-HARDWARE (flagged; this module is disabled by default):
#   - standalone emulator bin names + fullscreen flags (best-effort table below;
#     resolved with getExe' so they're eval-safe but runtime-checked) — verify
#     each on the deck.
#   - gamescope nesting (RetroFE SDL2/XWayland fullscreen + controller focus).
#   - bundled-layout name in the example tree (we keep the example's own
#     settings.conf layout= unless a custom theme is given).
{ config, lib, pkgs, ... }:
let
  cfg = config.modules.emulation;
  rcfg = cfg.retrofe;
  catalogue = import ./catalogue.nix;
  homeDir = "/home/${cfg.user}";

  enabledPlatforms = lib.filterAttrs (_n: p: p.enable) cfg.platforms;

  # Cores the enabled platforms use → shared RetroArch build (so its config dir
  # + assets exist); per-core launch still passes an explicit -L core path.
  chosenSpecs = lib.concatLists (lib.mapAttrsToList
    (name: p: map (e: catalogue.${name}.backends.${e}) p.emulators)
    enabledPlatforms);
  retroCores = lib.unique (map (s: s.core) (lib.filter (s: s ? core) chosenSpecs));
  retroarchBin =
    if retroCores != [ ]
    then lib.getExe (pkgs.retroarch.withCores (cores: map (n: cores.${n}) retroCores))
    else lib.getExe pkgs.retroarch;

  # Standalone launch table: bin name + the argument string that precedes the
  # ROM-path token. Best-effort — VERIFY on hardware (see header). getExe' is a
  # plain path join (no eval-time meta check), so wrong guesses fail at runtime,
  # not at `nix eval`.
  standaloneLaunch = {
    "pcsx2" = { bin = "pcsx2-qt"; pre = "-batch -fullscreen"; };
    "dolphin-emu" = { bin = "dolphin-emu"; pre = "-b -e"; };
    "rpcs3" = { bin = "rpcs3"; pre = "--no-gui"; };
    "cemu" = { bin = "cemu"; pre = "-f -g"; };
    "xemu" = { bin = "xemu"; pre = "-full-screen -dvd_path"; };
    "ppsspp" = { bin = "ppsspp-sdl"; pre = "--fullscreen"; };
    "melonds" = { bin = "melonDS"; pre = ""; };
    "desmume" = { bin = "desmume"; pre = ""; };
    "mgba" = { bin = "mgba-qt"; pre = "-f"; };
    "flycast" = { bin = "flycast"; pre = ""; };
    "azahar" = { bin = "azahar"; pre = ""; };
    "citron" = { bin = "citron"; pre = "-f -g"; };
    "eden" = { bin = "eden"; pre = "-f -g"; };
    "ryubing" = { bin = "ryubing"; pre = ""; };
    "shadps4" = { bin = "shadps4"; pre = ""; };
    "ares" = { bin = "ares"; pre = ""; };
    "mupen64plus" = { bin = "mupen64plus"; pre = "--fullscreen"; };
    "mame" = { bin = "mame"; pre = ""; }; # handled specially (rompath + %ITEM_NAME%)
  };

  romDirAbs = plat: "${homeDir}/Emulation/roms/${plat.romDir}";

  # ROM basename without extension (RetroFE matches per-game override confs on
  # this, case-sensitive). Keeps dots inside the name (only the last is the ext).
  romBase = f:
    let
      b = baseNameOf f;
      parts = lib.splitString "." b;
    in
    if lib.length parts <= 1 then b else lib.concatStringsSep "." (lib.init parts);

  launcherName = platName: key: "${platName}-${key}";

  # The launcher.conf body for one (platform, backend) pair.
  launcherConf = platName: plat: key:
    let
      spec = plat.backends.${key};
      isCore = spec ? core;
      isMame = (spec ? pkg) && (spec.pkg == "mame");
      coreWrapper = pkgs.writeShellScript "retrofe-ra-${platName}-${key}" ''
        # single .so in the per-core package → unambiguous glob (avoids guessing
        # the <core>_libretro.so filename).
        exec ${retroarchBin} -f -L ${pkgs.libretro.${spec.core}}/lib/retroarch/cores/*.so "$1"
      '';
      st = standaloneLaunch.${spec.pkg or ""} or { bin = spec.pkg or ""; pre = ""; };
      executable =
        if isCore then "${coreWrapper}"
        else lib.getExe' pkgs.${spec.pkg} st.bin;
      arguments =
        if isCore then ''"%ITEM_FILEPATH%"''
        else if isMame then ''-rp ${romDirAbs plat} "%ITEM_NAME%"''
        else lib.concatStringsSep " " (lib.filter (s: s != "") [ st.pre ''"%ITEM_FILEPATH%"'' ]);
    in
    ''
      executable = ${executable}
      arguments = ${arguments}
    '';

  # Per-platform collection settings.conf.
  collectionConf = platName: plat: p:
    ''
      list.extensions = ${lib.concatStringsSep "," plat.extensions}
      list.path = ${romDirAbs plat}
      launcher = ${launcherName platName (lib.head p.emulators)}
    '';

  # Per-game override confs for a platform: any { file; emulator; } whose
  # emulator differs from the platform primary.
  overrideGames = platName: p:
    lib.filter
      (g: !(builtins.isString g) && g.emulator != null && g.emulator != (lib.head p.emulators))
      p.games;

  themeName =
    if rcfg.theme != null then baseNameOf rcfg.theme else null;

  # ---- assemble the config tree as a store derivation ----------------------
  retrofeConfig = pkgs.runCommand "retrofe-config" { } ''
    set -euo pipefail
    # 1. seed from the package example tree (carries the default layouts)
    cp -r ${pkgs.retrofe}/share/retrofe/example $out
    chmod -R u+w $out
    mkdir -p $out/collections/Main $out/launchers

    # 2. main menu = enabled collections
    cat > $out/collections/Main/menu.txt <<'MENU'
    ${lib.concatStringsSep "\n" (lib.attrNames enabledPlatforms)}
    MENU

    # 3. per-platform collections + per-game override confs
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (platName: p:
      let plat = catalogue.${platName}; in ''
        mkdir -p "$out/collections/${platName}/launchers"
        cp ${pkgs.writeText "coll-${platName}.conf" (collectionConf platName plat p)} \
           "$out/collections/${platName}/settings.conf"
        ${lib.concatMapStringsSep "\n" (g: ''
          cp ${pkgs.writeText "ov-${platName}-${romBase g.file}.conf"
                "${launcherName platName g.emulator}"} \
             "$out/collections/${platName}/launchers/${romBase g.file}.conf"
        '') (overrideGames platName p)}
      '') enabledPlatforms)}

    # 4. one launcher.conf per (platform, backend)
    ${lib.concatStringsSep "\n" (lib.concatLists (lib.mapAttrsToList (platName: p:
      let plat = catalogue.${platName}; in
      map (key: ''
        cp ${pkgs.writeText "launch-${launcherName platName key}.conf"
              (launcherConf platName plat key)} \
           "$out/launchers/${launcherName platName key}.conf"
      '') p.emulators) enabledPlatforms))}

    # 5. optional global theme (custom layout) → set settings.conf layout=
    ${lib.optionalString (rcfg.theme != null) ''
      cp -r ${rcfg.theme} "$out/layouts/${themeName}"
      if grep -qE '^[[:space:]]*layout' "$out/settings.conf"; then
        sed -i 's|^[[:space:]]*layout.*|layout = ${themeName}|' "$out/settings.conf"
      else
        echo "layout = ${themeName}" >> "$out/settings.conf"
      fi
    ''}

    # 6. optional per-platform layouts → layouts/<active>/collections/<plat>/layout/
    ACTIVE_LAYOUT=$(grep -E '^[[:space:]]*layout' "$out/settings.conf" | head -1 | sed 's|.*=[[:space:]]*||' | tr -d '[:space:]')
    : "''${ACTIVE_LAYOUT:=Arcades}"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (platName: p:
      lib.optionalString (p.theme != null) ''
        mkdir -p "$out/layouts/$ACTIVE_LAYOUT/collections/${platName}/layout"
        cp -r ${p.theme}/. "$out/layouts/$ACTIVE_LAYOUT/collections/${platName}/layout/"
      '') enabledPlatforms)}
  '';

  # Wrapper: copy the read-only config tree to a writable persisted dir, set
  # RETROFE_PATH, exec there. ROMs/media stay external (collection list.path).
  retrofeWrapper = pkgs.writeShellScriptBin "retrofe-emulation" ''
    set -eu
    dest="''${XDG_DATA_HOME:-$HOME/.local/share}/retrofe"
    mkdir -p "$dest"
    # refresh declarative files from the Nix tree; leave RetroFE's own runtime
    # files (meta cache, logs) in place.
    cp -rfL --no-preserve=mode ${retrofeConfig}/. "$dest/"
    chmod -R u+w "$dest"
    cd "$dest"
    export RETROFE_PATH="$dest"
    exec ${lib.getExe' pkgs.retrofe "retrofe"} "$@"
  '';
in
{
  options.modules.emulation.retrofe = {
    theme = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Global RetroFE layout directory (a HyperSpin-style theme). Dropped into
        the config tree as layouts/<dirname>/ and selected via settings.conf
        `layout =`. null = keep the layout shipped in the package's example tree.
        Per-platform overrides: platforms.<name>.theme (placed under the active
        layout's collections/<name>/layout/).
      '';
    };

    steamShortcut = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Emit a desktop entry (RetroFE.desktop) launching the wrapper, so RetroFE
        appears in Plasma and can be imported into Steam as the SINGLE non-Steam
        shortcut (one Steam Input layout for the whole stack — see 03 §3.3).
        Writing shortcuts.vdf itself is a one-time Steam-ROM-Manager step (Steam
        must be exited); this only provides the launchable entry.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.frontend == "retrofe") {
    home-manager.users.${cfg.user} = {
      home.packages = [ retrofeWrapper pkgs.retrofe ];

      xdg.desktopEntries = lib.mkIf rcfg.steamShortcut {
        retrofe = {
          name = "RetroFE";
          genericName = "Emulation Frontend";
          comment = "Animated emulation frontend (drives the modules.emulation stack)";
          exec = "${lib.getExe retrofeWrapper}";
          icon = "applications-games";
          categories = [ "Game" ];
          terminal = false;
        };
      };
    };
  };
}
