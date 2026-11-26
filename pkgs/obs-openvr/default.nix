{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  obs-studio,
  openvr,
}:

# obs-openvr (github.com/alisonjenkins/obs-openvr, GPL-3.0): an OBS source that
# captures the SteamVR (OpenVR) headset mirror view, for streaming the Steam
# Frame view through OBS. This fork of icedream/obs-openvr makes the mirror
# source build at all, copies frames on the GPU, crops them itself and
# reconnects when SteamVR restarts. The fork has its own flake
# (nix/package.nix); this copy pins a commit so nix-config needs no extra
# flake input. To update: bump `rev`, then `hash` and `cargoHash`.
rustPlatform.buildRustPackage {
  pname = "obs-openvr";
  version = "0.2.0-unstable-2026-11-26";

  src = fetchFromGitHub {
    owner = "alisonjenkins";
    repo = "obs-openvr";
    rev = "0143ca25cb9b74af57f5a13b46a36f154a6eb8f4";
    hash = "sha256-R/MO73x6wE4yzA+vK9BssGC8l+PI6ZXOmxCeYF2+tE8=";
  };

  cargoHash = "sha256-KOgMlCMkOhmsR694w60f20/h6txwk3naT7RCXq2QIhM=";

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];
  buildInputs = [
    obs-studio
    openvr
  ];

  # No tests in the workspace; only the plugin crate is installed.
  doCheck = false;
  cargoBuildFlags = [ "-p" "obs-openvr" ];

  installPhase = ''
    runHook preInstall
    lib=$(find target -name libobs_openvr.so -path '*/release/*' | head -n1)
    install -Dm755 "$lib" $out/lib/obs-plugins/obs-openvr.so
    runHook postInstall
  '';

  meta = {
    description = "OBS source that captures the SteamVR (OpenVR) headset mirror view on Linux";
    homepage = "https://github.com/alisonjenkins/obs-openvr";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
