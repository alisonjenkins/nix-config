# Claude Desktop, repackaged from Anthropic's official Linux .deb.
# Design follows aaddrick/claude-desktop-debian's nix/claude-desktop.nix
# (MIT/Apache-2.0): keep the vendored Electron tree intact rather than
# running app.asar under nixpkgs' electron, and keep the Chromium sandbox.
#
# Update: read Version/SHA256 for both arches from
# https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-{amd64,arm64}/Packages
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  addDriverRunpath,
  makeWrapper,
  asar,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libgbm,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  pango,
  systemd,
  libcap_ng,
  libseccomp,
  libGL,
  libayatana-appindicator,
  libnotify,
  libpulseaudio,
  libsecret,
  libuuid,
  libxtst,
  pciutils,
  pipewire,
  wayland,
  bash,
  procps,
}:

let
  version = "4.29.0";

  poolBase = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop";

  srcs = {
    x86_64-linux = {
      url = "${poolBase}/claude-desktop_${version}_amd64.deb";
      hash = "sha256-SqD3Y9bAWseVAjkt1Q9df1xFWy8KQF1b3xVUrNg0Kok=";
    };
    aarch64-linux = {
      url = "${poolBase}/claude-desktop_${version}_arm64.deb";
      hash = "sha256-l4gVuBEJRIBbUM8Nvrn94+vTYcW4X97J3XQZgFRdELA=";
    };
  };

  # The bundle spawns these by absolute path; NixOS has no /usr/bin or
  # /bin/bash, so the agent shell and keyring lookups fail with ENOENT.
  hostHelpers = {
    "/usr/bin/secret-tool" = "${libsecret}/bin/secret-tool";
    "/usr/bin/busctl" = "${systemd}/bin/busctl";
    "/bin/ps" = "${procps}/bin/ps";
    "/usr/bin/pgrep" = "${procps}/bin/pgrep";
    "/bin/bash" = "${bash}/bin/bash";
  };

  # Fail the build if upstream re-minifies a literal away, rather than
  # shipping a stale path.
  rewriteHelper = literal: target: ''
    files=$(grep -rlF --include='*.js' '"${literal}"' "$work/app" || true)
    if [[ -z $files ]]; then
      echo "claude-desktop: literal \"${literal}\" not found in app.asar" >&2
      exit 1
    fi
    for f in $files; do
      substituteInPlace "$f" --replace-fail '"${literal}"' '"${target}"'
      patched+=("$f")
    done
    if grep -rqE "[\"'\`]${literal}[\"'\`]" "$work/app"; then
      echo "claude-desktop: literal ${literal} still present in app.asar" >&2
      exit 1
    fi
  '';
in
stdenv.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl (
    srcs.${stdenv.hostPlatform.system}
      or (throw "claude-desktop: unsupported system ${stdenv.hostPlatform.system}")
  );

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    asar
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libcap_ng
    libgbm
    libseccomp
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    stdenv.cc.cc.lib
    systemd
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
  ];

  # dlopen'd by the main process, not in DT_NEEDED.
  runtimeDependencies = map lib.getLib [
    libGL
    libayatana-appindicator
    libnotify
    libpulseaudio
    libsecret
    libuuid
    pciutils
    pipewire
    systemd
    wayland
    libxtst
  ];

  # chrome-sandbox is SUID in data.tar; dpkg-deb -x fails restoring it in
  # the build sandbox.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile "$src" \
      | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  # Copy the tree whole so /proc/self/exe and process.resourcesPath resolve
  # inside this store path. The bundled Vulkan loader only searches FHS ICD
  # dirs, hence VK_ADD_DRIVER_FILES.
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -a usr/lib usr/share $out/
    makeWrapper $out/lib/claude-desktop/claude-desktop \
      $out/bin/claude-desktop \
      --prefix VK_ADD_DRIVER_FILES : \
        "${addDriverRunpath.driverLink}/share/vulkan/icd.d"

    runHook postInstall
  '';

  # V8's compile cache would run the unpatched code if an edit kept the
  # source length, so drop it for patched files. asar pack never clears a
  # stale app.asar.unpacked, so pack into a fresh dir and diff the result.
  postInstall = ''
    resources=$out/lib/claude-desktop/resources
    work=$(mktemp -d)
    patched=()

    asar extract "$resources/app.asar" "$work/app"

    ${lib.concatStrings (lib.mapAttrsToList rewriteHelper hostHelpers)}

    for f in "''${patched[@]}"; do
      rm -f "$work/app/compile-cache/$(basename "$f")".*.jsc
    done

    (cd "$resources/app.asar.unpacked" && find . -type f | sort) \
      > "$work/unpacked"
    unpack="{$(sed "s|^\./|$work/app/|" "$work/unpacked" | paste -sd,)}"
    mkdir "$work/out"
    asar pack "$work/app" "$work/out/app.asar" --unpack "$unpack"

    diff -r "$resources/app.asar.unpacked" "$work/out/app.asar.unpacked"
    asar list --is-pack "$work/out/app.asar" \
      | sed -n 's|^unpack *: /|./|p' | sort | diff "$work/unpacked" -
    while read -r f; do
      chmod --reference="$resources/app.asar.unpacked/$f" \
        "$work/out/app.asar.unpacked/$f"
    done < "$work/unpacked"

    rm -r "$resources/app.asar" "$resources/app.asar.unpacked"
    mv "$work/out/app.asar" "$work/out/app.asar.unpacked" "$resources/"
    rm -r "$work"
  '';

  # The store cannot hold SUID, so chrome-sandbox ships 0755; Chromium uses
  # the user-namespace sandbox instead. Never add --no-sandbox.
  preFixup = ''
    addAutoPatchelfSearchPath "$out/lib/claude-desktop"
  '';

  # Bundled ANGLE dlopens libEGL.so.1 from its own runpath, not the main
  # ELF's, so runtimeDependencies alone leaves the GPU process crash-looping.
  appendRunpaths = [
    "${lib.getLib libGL}/lib"
    "${addDriverRunpath.driverLink}/lib"
  ];

  meta = {
    description = "Claude Desktop for Linux (repackaged official .deb)";
    homepage = "https://claude.ai";
    downloadPage = "https://downloads.claude.ai/claude-desktop/apt/stable";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames srcs;
    mainProgram = "claude-desktop";
  };
}
