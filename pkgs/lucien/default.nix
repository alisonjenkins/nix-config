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
    owner = "alisonjenkins";
    repo = "lucien";
    rev = "7213bb5a6999c533c9f06f865535c635bce0fc0d";
    hash = "sha256-+FEIACxl/qYQT7A1c0yEZ5Bvuyzgsfc6Spcair52zsw=";
  };

  useFetchCargoVendor = true;
  cargoHash = "sha256-issqRwT3hNGIQBzs3aBkGhMhrfGuNKW+IgRkHKo5WSw=";

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
