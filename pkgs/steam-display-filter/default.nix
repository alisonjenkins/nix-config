{ stdenv
, lib
}:

stdenv.mkDerivation {
  pname = "steam-display-filter";
  version = "1.0.0";

  src = ./.;

  # No X libraries, and none needed: the filter hooks two SDL entry points and
  # nothing else. It went the long way round through Xinerama and RandR first,
  # which is where those inputs came from; disassembling Steam showed the
  # routine that decides the capture geometry never touches Xlib.
  #
  # The SDL symbols are deliberately not linked either. They are resolved at
  # run time against whichever libSDL3 the host process already loaded, so
  # linking one here would pull a second copy into Steam's FHS environment.
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
    description = "Make Steam Remote Play stream at the client's resolution";
    longDescription = ''
      Steam Remote Play on Linux sizes its capture from its own idea of the
      desktop rather than from the PipeWire stream the portal gave it, so a
      client streaming a small virtual output still receives the desktop
      monitor's aspect ratio letterboxed into its frame.

      That idea of the desktop comes from SDL: Steam takes the union of every
      display SDL reports. Preloaded into the Steam client, this presents
      exactly one display, sized to the output being streamed and placed at the
      origin. It hooks SDL_GetDisplays and SDL_GetDisplayBounds and nothing
      else, applies only to the client itself rather than to games or gamescope
      launched from it, and does nothing at all unless a stream size has been
      published.

      Nothing in it is compositor-specific. Set STEAM_STREAM_SIZE=1280x800
      before starting Steam, or point STEAM_STREAM_TARGET at a file holding the
      same string for a watcher that learns the client's size on connect.
    '';
    platforms = lib.platforms.linux;
  };
}
