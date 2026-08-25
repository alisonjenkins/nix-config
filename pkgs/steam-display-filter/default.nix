{ stdenv
, lib
, libX11
, libXinerama
, libXrandr
}:

stdenv.mkDerivation {
  pname = "steam-display-filter";
  version = "1.0.0";

  src = ./.;

  buildInputs = [ libX11 libXinerama libXrandr ];

  # -shared with no -l for the interposed libraries on purpose: the symbols are
  # resolved through RTLD_NEXT at run time, against whichever libXinerama and
  # libXrandr the host process already loaded. Linking them here would pull a
  # second copy into Steam's FHS environment.
  buildPhase = ''
    runHook preBuild
    $CC -std=c11 -O2 -Wall -Wextra -fPIC -shared \
      -o libsteam-display-filter.so steam_display_filter.c -ldl
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 libsteam-display-filter.so \
      $out/lib/libsteam-display-filter.so
    runHook postInstall
  '';

  meta = {
    description = "Hide all but the streaming monitor from Steam Remote Play";
    longDescription = ''
      Steam Remote Play on Linux sizes its capture from the largest monitor X
      reports rather than from the PipeWire stream the portal gave it, so a
      client streaming a small virtual output still receives the desktop
      monitor's aspect ratio letterboxed into its frame. Neither the RandR
      primary flag nor the Xinerama head order changes this.

      Preloaded into Steam, this filters XineramaQueryScreens and
      XRRGetMonitors down to the output currently being streamed. It does
      nothing unless the host-side watcher has published a stream target, so
      ordinary desktop use is unaffected.
    '';
    platforms = lib.platforms.linux;
  };
}
