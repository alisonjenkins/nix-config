# Arsenal (rsnl-gg/HD2Arsenal) — the Helldivers 2 mod manager h2mm-cli
# (pkgs/h2mm-cli) deprecated itself in favor of on 2025-09-30. h2mm-cli has
# an unfixed, confirmed-reproducible bug (upstream issue #96: mods show
# ENABLED but have zero effect in-game, same symptom Arsenal doesn't have
# with the same mod) and its repo has had no code commits since the
# deprecation — Arsenal is the only maintained Linux-native option left.
# See the helldivers2-modding skill for the fuller incident writeup.
#
# Upstream ships this as an electron-builder .deb, zipped, no AppImage/
# tarball — fetchurl the zip, `dpkg-deb -x` the .deb inside it, then
# autoPatchelf the bundled (self-contained, not nixpkgs') Electron binary
# and its native node addons (better-sqlite3, sharp, active-win) against
# nixpkgs libs, following the same shape as nixpkgs' franz/generic.nix
# (used by ferdium et al) for electron-builder .deb repacks — not reused
# directly since that helper's unpackPhase assumes a bare .deb src, and
# upstream only publishes the zip-wrapped one.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook3,
  makeWrapper,
  unzip,
  dpkg,
  libxi,
  libxcursor,
  libxdamage,
  libxrandr,
  libxcomposite,
  libxext,
  libxfixes,
  libxrender,
  libx11,
  libxtst,
  libxscrnsaver,
  libgbm,
  gtk3,
  atk,
  glib,
  pango,
  gdk-pixbuf,
  cairo,
  freetype,
  fontconfig,
  dbus,
  nss,
  nspr,
  alsa-lib,
  cups,
  expat,
  udev,
  libnotify,
  xdg-utils,
  libglvnd,
  libappindicator-gtk3,
  pipewire,
  libpulseaudio,
  libuuid,
  libsecret,
  at-spi2-core,
}:
let
  runtimeDependencies = [
    libglvnd
    (lib.getLib stdenv.cc.cc)
    (lib.getLib udev)
    libnotify
    libappindicator-gtk3
    pipewire
    libpulseaudio
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "hd2arsenal";
  version = "0.36.2";

  src = fetchurl {
    url = "https://github.com/leguteape/hd2arsenal-release/releases/download/v${finalAttrs.version}/HD2Arsenal-Setup-DEB-${finalAttrs.version}.zip";
    hash = "sha256-spXwfDxvPQTni1OfhNDBaSrlNkB5CXGgRkpcGkZV0X8=";
  };

  dontUnpack = true;
  dontPatchELF = true;
  dontWrapGApps = true;

  # sharp bundles prebuilt libvips for every libc/arch combo and picks the
  # right one at require()-time; the musl-x64 variant (for Alpine, never
  # used on this glibc system) can't be patched against glibc's musl-free
  # library set, and doesn't need to be since it's never loaded here.
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
    unzip
    dpkg
  ];

  buildInputs = [
    libxi
    libxcursor
    libxdamage
    libxrandr
    libxcomposite
    libxext
    libxfixes
    libxrender
    libx11
    libxtst
    libxscrnsaver
    libgbm
    gtk3
    atk
    glib
    pango
    gdk-pixbuf
    cairo
    freetype
    fontconfig
    dbus
    nss
    nspr
    alsa-lib
    cups
    expat
    stdenv.cc.cc
    pipewire
    libpulseaudio
    libuuid
    libsecret
    at-spi2-core
  ];

  inherit runtimeDependencies;

  installPhase = ''
    runHook preInstall

    unzip -q "$src" -d deb-unpack
    dpkg-deb -x deb-unpack/hd2arsenal_${finalAttrs.version}_amd64.deb .

    mkdir -p $out/bin
    cp -r opt $out
    ln -s $out/opt/HD2Arsenal/hd2arsenal $out/bin/hd2arsenal

    cp -r usr/share $out
    substituteInPlace $out/share/applications/hd2arsenal.desktop \
      --replace-fail /opt/HD2Arsenal/hd2arsenal hd2arsenal

    runHook postInstall
  '';

  postFixup = ''
    wrapProgramShell $out/opt/HD2Arsenal/hd2arsenal \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeDependencies}" \
      --suffix PATH : ${xdg-utils}/bin \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-wayland-ime=true}}" \
      "''${gappsWrapperArgs[@]}"
  '';

  meta = {
    description = "Helldivers 2 mod manager, manifest builder, and lobby browser (successor to h2mm-cli)";
    homepage = "https://www.nexusmods.com/helldivers2/mods/4664";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hd2arsenal";
  };
})
