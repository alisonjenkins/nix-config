{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "obscura";
  version = "0.1.8";

  # Obscura embeds V8 via deno_core, which fetches a prebuilt librusty_v8
  # static lib at build time — building from source in the Nix sandbox is
  # painful. The publisher ships per-platform prebuilt binaries, so fetch
  # those instead (like pkgs/eden). The tarball contains two sibling
  # binaries: `obscura` (CLI + MCP server) and `obscura-worker` (the
  # browser subprocess obscura spawns from the same directory).
  system = stdenv.hostPlatform.system;

  sources = {
    x86_64-linux = {
      file = "obscura-x86_64-linux.tar.gz";
      hash = "sha256-5U0HBUBH1BgCR/A76gjRvXJO8YWYKTMaQz2pcvlzmIs=";
    };
    aarch64-linux = {
      file = "obscura-aarch64-linux.tar.gz";
      hash = "sha256-WGArgpOpPKpv2smKKGgpLJqR7KuG2DX5vSA2GsfkjqA=";
    };
    x86_64-darwin = {
      file = "obscura-x86_64-macos.tar.gz";
      hash = "sha256-NMvrlwbwr5Xef9ZpM0aj8dYBs13cPGI/Bgo2PprawgY=";
    };
    aarch64-darwin = {
      file = "obscura-aarch64-macos.tar.gz";
      hash = "sha256-36hPog4OM8exr53tGQzb+SjFpSo+2zCGAFleEUVe57s=";
    };
  };

  src' = sources.${system} or (throw "obscura: unsupported system ${system}");

  src = fetchurl {
    url = "https://github.com/h4ckf0r0day/obscura/releases/download/v${version}/${src'.file}";
    inherit (src') hash;
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  # Linux binaries are dynamically linked against libgcc_s/libm/libc — patch
  # them to the Nix store. macOS binaries are statically linked Rust (no
  # dylib path rewriting needed), so the original code signature stays valid.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 obscura "$out/bin/obscura"
    install -Dm755 obscura-worker "$out/bin/obscura-worker"
    runHook postInstall
  '';

  meta = {
    description = "Headless stealth browser for AI agents and web scraping (MCP server via `obscura mcp`)";
    homepage = "https://github.com/h4ckf0r0day/obscura";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    mainProgram = "obscura";
  };
}
