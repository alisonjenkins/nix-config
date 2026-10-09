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
in
rustPlatform.buildRustPackage rec {
  pname = "pdfcraft";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "pdfcraft";
    rev = "v${version}";
    hash = "sha256-Fkzo9qb9obrXa1X4klio+gRgM2UZIO8QwfI0/xSYwmo=";
  };

  cargoHash = "sha256-2y4jFVHDHUYoKo9gzRb7uq2dhtLa97P1iffRrMw46IQ=";

  cargoBuildFlags = [ "-p" "pdfcraft" ];
  doCheck = false;

  nativeBuildInputs = [
    pkg-config
    cmake
    makeWrapper
  ];

  buildInputs = runtimeLibs;

  postFixup = ''
    wrapProgram $out/bin/pdfcraft \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    description = "PDF reader and organizer in Rust";
    homepage = "https://github.com/storytold/pdfcraft";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
    mainProgram = "pdfcraft";
  };
}
