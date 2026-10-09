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
  pname = "filmcraft";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "filmcraft";
    rev = "v${version}";
    hash = "sha256-qM8o8rSiiGBif0UePQpn6aAEzqbjIMx3ZRoE3wA1yFI=";
  };

  cargoHash = "sha256-uzDeo+94RAK/flnYgTic167BeYfk2zqwwf/ODbwnok0=";

  cargoBuildFlags = [ "-p" "filmcraft" ];
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
    wrapProgram $out/bin/filmcraft \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    description = "FilmCraft desktop video editor in Rust";
    homepage = "https://github.com/storytold/filmcraft";
    license = with lib.licenses; [ asl20 mit ];
    platforms = lib.platforms.linux;
    mainProgram = "filmcraft";
  };
}
