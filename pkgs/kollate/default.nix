{
  lib,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  pkg-config,
  shaderc,
  spirv-headers,
  vulkan-headers,
  vulkan-loader,
}:

rustPlatform.buildRustPackage rec {
  pname = "kollate-cli";
  version = "0.7.1";

  src = fetchFromGitHub {
    owner = "andrew-lawlor";
    repo = "kollate";
    rev = "v${version}";
    hash = "sha256-+czY1A2mVLrp5Ui9oAWhp/uN41SKJLs83DUfgPytlEA=";
  };

  cargoHash = "sha256-iRyNWcuDe0AbFo2ukM2WTFnErgjAsBWb1GY9IP+59pU=";

  # The GTK app crate is skipped: only the CLI runs headless from the sync service.
  cargoBuildFlags = [ "-p" "kollate-cli" ];
  cargoTestFlags = [ "-p" "kollate-core" "-p" "kollate-cli" ];

  nativeBuildInputs = [
    cmake
    pkg-config
    shaderc
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    spirv-headers
    vulkan-headers
    vulkan-loader
  ];

  meta = {
    description = "Kobo highlights, markups and notebooks to Markdown/Obsidian (CLI only)";
    homepage = "https://github.com/andrew-lawlor/kollate";
    license = lib.licenses.gpl3Plus;
    mainProgram = "kollate-cli";
    platforms = [ "x86_64-linux" ];
  };
}
