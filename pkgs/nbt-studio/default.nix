# NBT Studio — GUI editor for Minecraft NBT files.
# Upstream is a .NET 6 WPF (Windows-only) application. Linux support comes
# from running it under Wine. The first launch installs the .NET 6 Desktop
# Runtime into a per-user Wine prefix via winetricks; subsequent launches
# skip that step.
#
# Set NBT_STUDIO_WINEPREFIX to override the prefix location (default:
# $XDG_DATA_HOME/nbt-studio/wine — typically ~/.local/share/nbt-studio/wine).
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  writeShellScript,
  wineWow64Packages,
  winetricks,
  cabextract,    # winetricks dep for some verbs
  p7zip,
  curl,
  bash,
}:

let
  version = "1.15.3";

  exe = fetchurl {
    url  = "https://github.com/tryashtar/nbt-studio/releases/download/v${version}/NbtStudio.exe";
    hash = "sha256-8yBKrXJlWvQQjNFh8ykim2Nhe0+vgbF4YLSZ5bkEfrk=";
  };

  wine = wineWow64Packages.stableFull;

  # PATH used by the launcher — keeps winetricks dependencies on $PATH
  # without leaking the build environment to the user's shell.
  runtimePath = lib.makeBinPath [
    wine
    winetricks
    cabextract
    p7zip
    curl
    bash
  ];

  launcher = writeShellScript "nbt-studio-launcher" ''
    set -euo pipefail

    : "''${XDG_DATA_HOME:=$HOME/.local/share}"
    PREFIX="''${NBT_STUDIO_WINEPREFIX:-$XDG_DATA_HOME/nbt-studio/wine}"

    export PATH="${runtimePath}:$PATH"
    export WINEPREFIX="$PREFIX"
    export WINEDEBUG="''${WINEDEBUG:--all}"
    export WINEARCH=win64
    # Skip wine's first-run mono / gecko dialogs.
    export WINEDLLOVERRIDES="mscoree=d;mshtml=d"

    mkdir -p "$PREFIX"

    if [ ! -f "$PREFIX/.dotnet6-installed" ]; then
      echo "[nbt-studio] First run: bootstrapping Wine prefix and installing"
      echo "[nbt-studio] .NET 6 Desktop Runtime. This takes 1-2 minutes and"
      echo "[nbt-studio] only happens once. Prefix: $PREFIX"
      # wineboot to materialise an empty prefix before winetricks pokes at it
      wineboot --init >/dev/null 2>&1 || true
      winetricks -q dotnetdesktop6
      touch "$PREFIX/.dotnet6-installed"
      echo "[nbt-studio] .NET 6 ready. Launching NBT Studio..."
    fi

    exec wine64 ${exe} "$@"
  '';

  desktopItem = makeDesktopItem {
    name        = "nbt-studio";
    desktopName = "NBT Studio";
    comment     = "Editor for Minecraft NBT files";
    exec        = "nbt-studio %F";
    icon        = "nbt-studio";
    categories  = [ "Utility" "Development" "Game" ];
    mimeTypes   = [
      "application/x-nbt"
      "application/x-minecraft-region"
    ];
    keywords    = [ "minecraft" "nbt" "schematic" "level.dat" ];
  };

in
stdenvNoCC.mkDerivation {
  pname = "nbt-studio";
  inherit version;

  # No conventional source tarball — the upstream artifact is a bare .exe.
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper copyDesktopItems ];

  desktopItems = [ desktopItem ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/nbt-studio
    cp ${exe} $out/share/nbt-studio/NbtStudio.exe
    install -m755 ${launcher} $out/bin/nbt-studio

    runHook postInstall
  '';

  meta = {
    description = "GUI editor for Minecraft NBT files (run under Wine)";
    longDescription = ''
      NBT Studio is a tree-view editor for the Named Binary Tag (NBT) format
      used by Minecraft for level.dat, player data, structure / schematic
      files, and item NBT. The upstream is a Windows .NET 6 WPF application;
      this package launches it under Wine. On first run, a per-user Wine
      prefix is created and winetricks installs the required .NET 6 Desktop
      Runtime — this is a one-time ~2 minute step.
    '';
    homepage    = "https://github.com/tryashtar/nbt-studio";
    license     = lib.licenses.mit;
    platforms   = lib.platforms.linux;
    mainProgram = "nbt-studio";
    maintainers = [ ];
  };
}
