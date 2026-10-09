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
  pname = "photocraft";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "photocraft";
    rev = "v${version}";
    hash = "sha256-Ye8Fv4CPBUtqi1ZAJvXfpvyaXk7Ga9BAwl2nrsLEZWA=";
  };

  cargoHash = "sha256-Id7pMLTkMvW/3/CESTGnWpdVVoF7yJLnbNMTQVt8n3s=";

  cargoBuildFlags = [ "-p" "photocraft" ];
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
    wrapProgram $out/bin/photocraft \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    description = "Open-source Photoshop-style image editor in Rust";
    homepage = "https://github.com/storytold/photocraft";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
    mainProgram = "photocraft";
  };
}
