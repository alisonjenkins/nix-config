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
  pname = "lightcraft";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "lightcraft";
    rev = "v${version}";
    hash = "sha256-6/MxXgVN+1IPj4i/tjpUvP0xAKk22cuY7p6WQraZ1ug=";
  };

  cargoHash = "sha256-Z6r3NGsYyE/bdTzuPFjUba6YsxCl9qieDrICeqFpo/A=";

  cargoBuildFlags = [ "-p" "lightcraft" ];
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
  ];

  postFixup = ''
    wrapProgram $out/bin/lightcraft \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    description = "Open-source photo library and raw developer in Rust";
    homepage = "https://github.com/storytold/lightcraft";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
    mainProgram = "lightcraft";
  };
}
