{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  gtk3,
  glib,
  pango,
  cairo,
  harfbuzz,
  atk,
  gdk-pixbuf,
  libepoxy,
  fontconfig,
  libGL,
  libx11,
  zlib,
  openssl,
  libffi,
  xz,
  bzip2,
  sqlite,
  ncurses,
  expat,
  libuuid,
  openjdk21_headless,
  openssh,
  android-tools,
  xdg-utils,
  wl-clipboard,
  desktop-file-utils,
}:

# FramePort (https://github.com/spoopyghosty0/frameport, GPL-3.0-only): ports
# Meta Quest standalone APKs to the Steam Frame (VrApi -> OpenXR via OVRPort,
# re-signs, installs into Valve's Lepton container over SSH). Not in nixpkgs.
#
# Upstream's Linux release is a `flet build` Flutter bundle with its own
# Python 3.14 and wheels, so this patches that bundle instead of rebuilding
# Flet/Flutter from source.
#
# At runtime it fetches its own JRE, OVRPort CLI jar and apksigner into
# ~/.local/share/frameport/tools. The jars are plain Java, but a downloaded
# Temurin JRE would not run on NixOS, so FRAMEPORT_JAVA points at nixpkgs'.
stdenv.mkDerivation (finalAttrs: {
  pname = "frameport";
  version = "1.4.1";

  src = fetchurl {
    url = "https://github.com/spoopyghosty0/frameport/releases/download/v${finalAttrs.version}/FramePort-linux-x64.tar.gz";
    # Matches the release's SHA256SUMS.txt.
    hash = "sha256-cDJLuhplV8PK45pIau5xhMF+toPRabYP4uhQ0HQvlFM=";
  };

  sourceRoot = "FramePort";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    gtk3
    glib
    pango
    cairo
    harfbuzz
    atk
    gdk-pixbuf
    libepoxy
    fontconfig
    libGL
    libx11
    zlib
    openssl
    libffi
    xz
    bzip2
    sqlite
    ncurses
    expat
    libuuid
  ];

  # libdartjni (JNI) is only used by Flutter on Android; _tkinter is unused.
  autoPatchelfIgnoreMissingDeps = [ "libjvm.so" "libtcl9tk9.0.so" "libtcl9.0.so" ];

  dontBuild = true;
  dontConfigure = true;
  # Stripping the Flutter AOT snapshot (lib/libapp.so) breaks it.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/frameport
    cp -r . $out/lib/frameport/
    install -Dm444 data/app_icon.png $out/share/icons/hicolor/512x512/apps/frameport.png

    # The Flutter host resolves data/ and lib/ next to its own executable,
    # so the real binary stays in the bundle and the wrapper points at it.
    makeWrapper $out/lib/frameport/FramePort $out/bin/frameport \
      --set FRAMEPORT_JAVA ${lib.getExe' openjdk21_headless "java"} \
      --set FRAMEPORT_NO_UPDATE_CHECK 1 \
      --prefix PATH : ${lib.makeBinPath [ openssh android-tools xdg-utils wl-clipboard desktop-file-utils ]}

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "frameport";
      desktopName = "FramePort";
      comment = "Run Meta Quest games on the Steam Frame";
      exec = "frameport";
      icon = "frameport";
      categories = [ "Game" "Utility" ];
      startupWMClass = "FramePort";
    })
  ];

  meta = {
    description = "Port Meta Quest standalone games to the Valve Steam Frame";
    homepage = "https://github.com/spoopyghosty0/frameport";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode lib.sourceTypes.binaryBytecode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "frameport";
  };
})
