{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
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
  pname = "vectorcraft";
  version = "0.7.0";

  src = fetchFromGitHub {
    owner = "storytold";
    repo = "vectorcraft";
    rev = "v${version}";
    hash = "sha256-W76TxJHWIfLwFmocahH8MCaWARGJYS6q3YLJNoWb0AI=";
  };

  cargoHash = "sha256-mCTuARKTk/8Dhiefool5VAUlYEM+tSu4tkUTnmlKaLY=";

  cargoBuildFlags = [ "-p" "vectorcraft" ];
  doCheck = false;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = runtimeLibs;

  postFixup = ''
    wrapProgram $out/bin/vectorcraft \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    description = "Open-source vector graphics editor in Rust";
    homepage = "https://github.com/storytold/vectorcraft";
    license = with lib.licenses; [ mit asl20 ];
    platforms = lib.platforms.linux;
    mainProgram = "vectorcraft";
  };
}
