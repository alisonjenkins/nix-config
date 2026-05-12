{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  makeBinaryWrapper,
  moltenvk,
  vulkan-loader,
}:

let
  pname = "eden";
  version = "0.2.0-rc2";

  linuxSrc = fetchurl {
    url = "https://stable.eden-emu.dev/v${version}/Eden-Linux-v${version}-amd64-clang-pgo.AppImage";
    hash = "sha256-/4qSE97tO9klkmliAJzR4UnnYPrdSqmzrwItFoQaiAU=";
  };

  darwinSrc = fetchurl {
    url = "https://stable.eden-emu.dev/v${version}/Eden-macOS-v${version}.tar.gz";
    hash = "sha256-aYeUSvSDgGZ8cWpVsjdiCHLYQCyYrNj4Q0bSeNhzMcs=";
  };

  meta = {
    description = "Yuzu fork Nintendo Switch emulator (active community continuation, Android-first)";
    homepage = "https://eden-emu.dev/";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
    mainProgram = "eden";
  };

  linuxPkg = appimageTools.wrapType2 {
    inherit pname version meta;
    src = linuxSrc;
  };

  darwinPkg = stdenv.mkDerivation {
    inherit pname version meta;
    src = darwinSrc;

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [ makeBinaryWrapper ];

    # Eden's macOS bundle ships only libMoltenVK, no Vulkan loader. Citron's
    # vulkan_library.cpp (same code path in Eden) tries LIBVULKAN_PATH, then
    # Frameworks/libvulkan.1.dylib, then Frameworks/libMoltenVK.dylib. Without
    # the loader, the VK_KHR_portability_enumeration instance extension isn't
    # available and instance creation fails. Point Eden at the Nix Vulkan
    # loader + MoltenVK ICD so the loader exposes portability_enumeration.
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications"
      cp -R eden.app "$out/Applications/eden.app"
      mkdir -p "$out/bin"
      makeWrapper "$out/Applications/eden.app/Contents/MacOS/eden" "$out/bin/eden" \
        --set-default LIBVULKAN_PATH ${vulkan-loader}/lib/libvulkan.1.dylib \
        --set-default VK_ICD_FILENAMES ${moltenvk}/share/vulkan/icd.d/MoltenVK_icd.json
      runHook postInstall
    '';
  };
in
if stdenv.hostPlatform.isDarwin then darwinPkg else linuxPkg
