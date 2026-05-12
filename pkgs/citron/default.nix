{
  lib,
  stdenv,
  fetchgit,
  cmake,
  ninja,
  pkg-config,
  python3,
  autoconf,
  automake,
  libtool,
  git,
  gnumake,
  coreutils,
  glslang,
  qt6,
  SDL2,
  boost,
  openssl,
  zlib,
  zstd,
  lz4,
  nlohmann_json,
  fmt,
  ffmpeg,
  vulkan-headers,
  vulkan-loader,
  openal,
  libusb1 ? null,
  alsa-lib ? null,
  libpulseaudio ? null,
  moltenvk ? null,
  darwin ? null,
}:

let
  isDarwin = stdenv.hostPlatform.isDarwin;
  isLinux = stdenv.hostPlatform.isLinux;
in
stdenv.mkDerivation {
  pname = "citron";
  version = "0-unstable-2026-05-12";

  src = fetchgit {
    url = "https://github.com/citron-neo/emulator";
    rev = "d02a93ef21c66ea96c5461d949263a3c7887d711";
    hash = "sha256-LZuasWjGpaXbgS61fltxfpjV/hEwp1qTQDEEROhqYAQ=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    python3
    autoconf
    automake
    libtool
    git
    gnumake
    coreutils
    glslang
    qt6.wrapQtAppsHook
    qt6.qttools
  ] ++ lib.optionals isDarwin [
    darwin.bootstrap_cmds
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtmultimedia
    SDL2
    boost
    openssl
    zlib
    zstd
    lz4
    nlohmann_json
    fmt
    ffmpeg
    vulkan-headers
    openal
  ] ++ lib.optionals isLinux [
    qt6.qtwayland
    vulkan-loader
    libusb1
    alsa-lib
    libpulseaudio
  ] ++ lib.optionals isDarwin [
    moltenvk
    vulkan-loader
  ];

  # On Darwin, citron needs the Vulkan loader (not MoltenVK direct) so that
  # the VK_KHR_portability_enumeration instance extension is available — that
  # extension is exposed by the loader, not by MoltenVK itself. Point
  # citron at libvulkan and tell the loader where MoltenVK's ICD lives.
  qtWrapperArgs = lib.optionals isDarwin [
    "--set-default LIBVULKAN_PATH ${vulkan-loader}/lib/libvulkan.1.dylib"
    "--set-default VK_ICD_FILENAMES ${moltenvk}/share/vulkan/icd.d/MoltenVK_icd.json"
  ];

  preConfigure = ''
    # nx_tzdb's tz submodule does `git clone file://...tz` from the source tree,
    # but Nix sources have no .git. Initialize tz/ as a real repo so the clone
    # in tzdb_to_nx/externals/tz/CMakeLists.txt succeeds inside the sandbox.
    if [ -d externals/nx_tzdb/tzdb_to_nx/externals/tz/tz ] && [ ! -d externals/nx_tzdb/tzdb_to_nx/externals/tz/tz/.git ]; then
      (
        cd externals/nx_tzdb/tzdb_to_nx/externals/tz/tz
        git init -q
        git config user.email nix@build
        git config user.name nix
        git add -A
        git commit -q -m "vendor"
      )
    fi
  '';

  # Citron's CMake install(TARGETS) is gated `UNIX AND NOT APPLE`, so the
  # default install does nothing on Darwin. Copy the .app bundle ourselves.
  # Also bundle libvulkan.1.dylib next to libMoltenVK.dylib so citron's
  # dlopen("Contents/Frameworks/libvulkan.1.dylib") succeeds before falling
  # through to DYLD_* env (which macOS hardening may strip).
  installPhase = lib.optionalString isDarwin ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R bin/citron.app "$out/Applications/Citron.app"
    mkdir -p "$out/bin"
    ln -s "$out/Applications/Citron.app/Contents/MacOS/citron" "$out/bin/citron"
    runHook postInstall
  '';

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DUSE_SYSTEM_QT=ON"
    "-DCITRON_USE_BUNDLED_VCPKG=OFF"
    "-DCITRON_TESTS=OFF"
    "-DCITRON_USE_FASTER_LD=OFF"
    "-DCITRON_CHECK_SUBMODULES=OFF"
    "-DCITRON_ENABLE_LTO=OFF"
    "-DUSE_DISCORD_PRESENCE=OFF"
    "-DENABLE_QT_TRANSLATION=ON"
    "-DCITRON_USE_QT_MULTIMEDIA=ON"
    "-DENABLE_WEB_SERVICE=OFF"
  ];

  meta = {
    description = "Yuzu fork Nintendo Switch emulator (post-Yuzu continuation)";
    homepage = "https://citron-emu.org/";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" "aarch64-darwin" ];
    mainProgram = "citron";
  };
}
