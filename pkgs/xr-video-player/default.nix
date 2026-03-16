{
  lib,
  stdenv,
  fetchFromGitea,
  cmake,
  pkg-config,
  SDL2,
  glm,
  libepoxy,
  libGL,
  libdrm,
  openxr-loader,
  wayland,
  pipewire,
  glib,
  mpv,
}:

stdenv.mkDerivation {
  pname = "xr-video-player";
  version = "0-unstable-2026-01-20";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "yoshino";
    repo = "xr-video-player";
    rev = "d3fb486f4615bd365b39e7ca4b855a612cca5612";
    hash = "sha256-3t2Ed1wWbe55ugR5O4QO4fmCI3muXlmozgX60ySydo0=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    SDL2
    glm
    libepoxy
    libdrm
    libGL
    openxr-loader
    wayland
    pipewire
    glib
    mpv
  ];

  meta = {
    description = "OpenXR/Wayland VR video player for stereoscopic videos and games on Linux";
    homepage = "https://codeberg.org/yoshino/xr-video-player";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "xr-video-player";
  };
}
