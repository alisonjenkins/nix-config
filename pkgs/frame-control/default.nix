{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
  writeShellApplication,
  openssh,
  rsync,
}:

# Frame Control (https://github.com/saphid/frame-control, MIT): manages a
# Steam Frame from the PC over SSH, including sideloading APKs and Linux
# ARM64 zips. It reads FrameDrop's `framedrop.install/v1` manifests, but only
# registers `frame-control://` links. FrameDrop itself (framedropvr.com) is
# Windows-only, so `framedrop-handler` below takes the `framedrop://` links
# that "Install with FrameDrop" buttons open and hands them to Frame Control.
let
  pname = "frame-control";
  version = "0.4.62";

  src = fetchurl {
    url = "https://github.com/saphid/frame-control/releases/download/v${version}/Frame-Control-linux-x86_64.AppImage";
    # Matches the digest in the release's update.json.
    hash = "sha256-/RV3XTQyXbD7t7QS4TWzjVLbZCx3kItkYeXH9ac4gio=";
  };

  contents = appimageTools.extractType2 { inherit pname version src; };

  # `framedrop://install?manifest=…` -> `frame-control://install?manifest=…`.
  # Only the scheme is rewritten; Frame Control's own parser
  # (app/install-link.js) and server (ui/frame_webinstall.py) still apply
  # their full checks (single manifest/url key, HTTPS, no private addresses,
  # size cap, sha256).
  framedropHandler = writeShellApplication {
    name = "framedrop-handler";
    text = ''
      link="''${1:-}"
      case "$link" in
        [Ff][Rr][Aa][Mm][Ee][Dd][Rr][Oo][Pp]://*) ;;
        *)
          echo "framedrop-handler: expected a framedrop:// link, got: $link" >&2
          exit 64
          ;;
      esac
      exec "@out@/bin/frame-control" "frame-control:''${link#*:}"
    '';
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  # Setup and every transfer shell out to ssh/scp/rsync on the PC. adb ships
  # inside the AppImage (resources/tools/adb).
  extraPkgs = _: [ openssh rsync ];

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    # Usage analytics go to PostHog by default once the first-run notice has
    # been shown (ui/frame_telemetry.py). Both variables turn every level off.
    # The in-app updater can't replace a store path: without $APPIMAGE set it
    # falls back to opening the release page, so updates come through here.
    wrapProgram $out/bin/${pname} \
      --set DO_NOT_TRACK 1 \
      --set FRAME_CONTROL_TELEMETRY 0

    install -Dm444 ${contents}/frame-control.desktop $out/share/applications/frame-control.desktop
    substituteInPlace $out/share/applications/frame-control.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} %U'
    install -Dm444 ${contents}/frame-control.png $out/share/icons/hicolor/512x512/apps/frame-control.png

    install -Dm555 ${lib.getExe framedropHandler} $out/bin/framedrop-handler
    substituteInPlace $out/bin/framedrop-handler --replace-fail '@out@' "$out"
    cat > $out/share/applications/framedrop-handler.desktop <<DESKTOP
    [Desktop Entry]
    Type=Application
    Name=FrameDrop links (Frame Control)
    Comment=Open Install with FrameDrop links in Frame Control
    Exec=$out/bin/framedrop-handler %u
    Icon=frame-control
    NoDisplay=true
    Terminal=false
    MimeType=x-scheme-handler/framedrop;
    DESKTOP
  '';

  meta = {
    description = "Manage and sideload to a Valve Steam Frame over SSH, with FrameDrop install-link support";
    homepage = "https://github.com/saphid/frame-control";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
