{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  cmake,
  makeWrapper,
  wayland,
  libxkbcommon,
  vulkan-loader,
  libGL,
  libx11,
  libxcursor,
  libxrandr,
  libxi,
  libxcb,
  fontconfig,
  freetype,
  gtk3,
  alsa-lib,
}:

let
  runtimeLibs = [
    wayland
    libxkbcommon
    vulkan-loader
    libGL
    libx11
    libxcursor
    libxrandr
    libxi
    libxcb
  ];

  filmcraftCrates = [
    "filmcraft-aac"
    "filmcraft-ac3"
    "filmcraft-av1"
    "filmcraft-bitstream"
    "filmcraft-cfb"
    "filmcraft-codecs"
    "filmcraft-color"
    "filmcraft-dnx"
    "filmcraft-frame"
    "filmcraft-geom"
    "filmcraft-h264"
    "filmcraft-h264enc"
    "filmcraft-hevc"
    "filmcraft-interchange"
    "filmcraft-isobmff"
    "filmcraft-matroska"
    "filmcraft-media"
    "filmcraft-mpeg2v"
    "filmcraft-mpegts"
    "filmcraft-mxf"
    "filmcraft-ogg"
    "filmcraft-opus"
    "filmcraft-project"
    "filmcraft-prores"
    "filmcraft-time"
    "filmcraft-vp9"
  ];
in
rustPlatform.buildRustPackage rec {
  pname = "effectcraft";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "effectcraft";
    rev = "v${version}";
    hash = "sha256-O3s4cFkqcQS3+xxby/oY7uqkBLbQsRsPR1xQsw+5FQ8=";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = lib.genAttrs (map (crate: "${crate}-0.1.1") filmcraftCrates) (_: "sha256-WXiX4rF7zSwfu3yu9aNH2/xWYhAYFVX1rdrnccuTD7g=");
  };

  cargoBuildFlags = [ "-p" "effectcraft" ];
  doCheck = false;

  nativeBuildInputs = [
    pkg-config
    cmake
    makeWrapper
  ];

  buildInputs = runtimeLibs ++ [
    fontconfig
    freetype
    gtk3
    alsa-lib
  ];

  postFixup = ''
    wrapProgram $out/bin/effectcraft \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    description = "Open-source motion graphics and VFX app in Rust";
    homepage = "https://github.com/storytold/effectcraft";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
    mainProgram = "effectcraft";
  };
}
