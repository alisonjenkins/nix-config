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
in
rustPlatform.buildRustPackage rec {
  pname = "designcraft";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "designcraft";
    rev = "v${version}";
    hash = "sha256-rissTTWbEe7ugm030syYmoquNVf9PNUPn0fdd4Eo02k=";
  };

  cargoHash = "sha256-GbQHf8GVm8nB8fcGcIDyhWJY/um9W4y1KRryUd574ws=";

  cargoBuildFlags = [ "-p" "designcraft" ];
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
    wrapProgram $out/bin/designcraft \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    description = "Page layout and publishing app in Rust";
    homepage = "https://github.com/storytold/designcraft";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
    mainProgram = "designcraft";
  };
}
