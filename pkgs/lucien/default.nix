{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  cmake,
  makeWrapper,
  wayland,
  wayland-protocols,
  libxkbcommon,
  vulkan-loader,
  libGL,
  fontconfig,
  freetype,
  expat,
  glib,
  gtk3,
}:

rustPlatform.buildRustPackage rec {
  pname = "lucien";
  version = "0-unstable-2025-05-22";

  src = fetchFromGitHub {
    owner = "Wachamuli";
    repo = "lucien";
    rev = "072e24556188c2a434e513d7437354ceffeb1cc9";
    hash = "sha256-Zvr653Ymu8Fkr2pXSDCfx084gfI+mEqBV8UhwZhs5nU=";
  };

  useFetchCargoVendor = true;
  cargoHash = "sha256-XEEokIcbNE1TCloJpzKzO4pqS7c0XTra1676RFH0gao=";

  nativeBuildInputs = [
    pkg-config
    cmake
    makeWrapper
  ];

  buildInputs = [
    wayland
    wayland-protocols
    libxkbcommon
    vulkan-loader
    libGL
    fontconfig
    freetype
    expat
    glib
    gtk3
  ];

  postFixup = ''
    wrapProgram $out/bin/lucien \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
        wayland
        libxkbcommon
        vulkan-loader
        libGL
      ]}
  '';

  meta = with lib; {
    description = "A lightweight Wayland application launcher";
    homepage = "https://github.com/Wachamuli/lucien";
    license = licenses.gpl3Only;
    maintainers = [];
    platforms = platforms.linux;
    mainProgram = "lucien";
  };
}
