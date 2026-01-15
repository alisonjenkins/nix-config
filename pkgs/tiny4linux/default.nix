{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  rustPlatform,
  pkg-config,
  copyDesktopItems,
  makeDesktopItem,
  # GUI dependencies
  libGL,
  libxkbcommon,
  vulkan-loader,
  wayland,
  xorg,
  # Optional features
  withGui ? true,
  withCli ? true,
}:
rustPlatform.buildRustPackage rec {
  pname = "tiny4linux";
  version = "2.2.1";

  src = fetchFromGitHub {
    owner = "OpenFoxes";
    repo = "Tiny4Linux";
    rev = "v${version}";
    hash = "sha256-eNvFa8h3XDnaSdM1iU6zbncUqBXzPrXgPzPziHJkZLA=";
  };

  cargoHash = "sha256-ZURy8sn2ljW6qrLt5ILM8vnRKCUhYqWdy1s8pExDDnc=";

  # Icons for desktop integration
  icon = fetchurl {
    url = "https://raw.githubusercontent.com/OpenFoxes/Tiny4Linux-Icons/main/generated/png/title-icon/v2.0-soft-shadow.png";
    hash = "sha256-VSYcvrTUGAnrjx536qdcNk88yOGjm7TZSjEmKRhOV40=";
  };

  iconWidget = fetchurl {
    url = "https://raw.githubusercontent.com/OpenFoxes/Tiny4Linux-Icons/main/generated/png/title-icon/v2.0-widget.png";
    hash = "sha256-gwgxf2DdYXZsuBf4R4mTvR1MWTwZqRVUtWtdW6IAKCM=";
  };

  nativeBuildInputs =
    [
      pkg-config
    ]
    ++ lib.optional withGui pkgs.makeWrapper
    ++ lib.optional withGui copyDesktopItems;

  buildInputs = lib.optionals withGui [
    libGL
    libxkbcommon
    vulkan-loader
    wayland
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr
  ];

  desktopItems = lib.optionals withGui [
    (makeDesktopItem {
      name = "tiny4linux-dashboard";
      desktopName = "Tiny4Linux";
      comment = "A graphical user interface for OBSBOT Tiny devices";
      exec = "tiny4linux-gui";
      icon = "tiny4linux";
      terminal = false;
      categories = [ "Utility" "System" ];
      keywords = [ "linux" "obsbot" "tiny" "utility" ];
    })
    (makeDesktopItem {
      name = "tiny4linux-widget";
      desktopName = "Tiny4Linux (Widget)";
      comment = "A graphical user interface for OBSBOT Tiny devices opened in widget mode";
      exec = "tiny4linux-gui --start-as widget";
      icon = "tiny4linux-widget";
      terminal = false;
      categories = [ "Utility" "System" ];
      keywords = [ "linux" "obsbot" "tiny" "utility" ];
    })
  ];

  # Build only the requested features
  cargoBuildFlags =
    lib.optionals withGui ["--features" "gui" "--bin" "tiny4linux-gui"]
    ++ lib.optionals withCli ["--features" "cli" "--bin" "tiny4linux-cli"];

  # Don't run tests during build
  doCheck = false;

  # Wrap GUI binary with library paths and install icons if GUI is enabled
  postInstall =
    lib.optionalString withGui ''
      wrapProgram $out/bin/tiny4linux-gui \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        libGL
        libxkbcommon
        vulkan-loader
        wayland
        xorg.libX11
        xorg.libXcursor
        xorg.libXi
        xorg.libXrandr
      ]}"

      # Install icons
      install -Dm644 ${icon} $out/share/icons/hicolor/256x256/apps/tiny4linux.png
      install -Dm644 ${iconWidget} $out/share/icons/hicolor/256x256/apps/tiny4linux-widget.png
    '';

  meta = {
    description = "GUI and CLI controller for the OBSBOT Tiny2 camera on Linux";
    longDescription = ''
      Tiny4Linux provides both graphical and command-line interfaces to control
      the OBSBOT Tiny2 camera on Linux. Features include sleep/wake toggle,
      tracking speed controls, and preset position management.
    '';
    homepage = "https://github.com/OpenFoxes/Tiny4Linux";
    license = lib.licenses.eupl12;
    maintainers = [];
    platforms = lib.platforms.linux;
    mainProgram = if withGui then "tiny4linux-gui" else "tiny4linux-cli";
  };
}
