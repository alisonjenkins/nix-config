{
  lib,
  rustPlatform,
  pkg-config,
  wayland,
  stasisSrc,
  ...
}:
rustPlatform.buildRustPackage {
  pname = "stasis";
  version = "unstable";

  src = stasisSrc;

  cargoLock = {
    lockFile = "${stasisSrc}/Cargo.lock";
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    wayland
  ];

  meta = with lib; {
    description = "Wayland idle manager";
    homepage = "https://github.com/saltnpepper97/stasis";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
