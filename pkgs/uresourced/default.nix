{ lib
, stdenv
, fetchFromGitLab
, meson
, ninja
, pkg-config
, glib
, systemd
, pipewire
, enableAppManagement ? true
, enableCgroupify ? true
}:

stdenv.mkDerivation rec {
  pname = "uresourced";
  version = "0.5.4";

  src = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "benzea";
    repo = "uresourced";
    rev = "v${version}";
    hash = "sha256-WTTQYk8tADY9BIfeQ5kFuBbODbRWW8/YCw3vp6O032o=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    glib # for glib-compile-resources
  ];

  buildInputs = [
    glib
    systemd
  ] ++ lib.optional enableAppManagement pipewire;

  mesonFlags = [
    "-Dsystemdsystemunitdir=${placeholder "out"}/lib/systemd/system"
    "-Dsystemduserunitdir=${placeholder "out"}/lib/systemd/user"
    "-Dappmanagement=${lib.boolToString enableAppManagement}"
    "-Dcgroupify=${lib.boolToString enableCgroupify}"
  ];

  meta = with lib; {
    description = "User resource assignment daemon for graphical sessions";
    homepage = "https://gitlab.freedesktop.org/benzea/uresourced";
    license = licenses.lgpl21Plus;
    platforms = platforms.linux;
    maintainers = [];
  };
}
