{ lib
, stdenv
, fetchFromGitHub
, makeWrapper
, kmod
, binutils
, util-linux
, coreutils
, bash
}:

stdenv.mkDerivation rec {
  pname = "kpatch";
  version = "0.9.9";

  src = fetchFromGitHub {
    owner = "dynup";
    repo = "kpatch";
    rev = "v${version}";
    hash = "sha256-D3hCcjT0kHMmBHgMFFmFyP5hQrJJnLghoKbJ7chOZfs=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # Only build the runtime utility, not kpatch-build
  buildPhase = "true";

  installPhase = ''
    install -Dm755 kpatch/kpatch $out/sbin/kpatch
    install -Dm644 contrib/kpatch.service $out/lib/systemd/system/kpatch.service

    substituteInPlace $out/lib/systemd/system/kpatch.service \
      --replace-fail "PREFIX/sbin" "$out/sbin"

    wrapProgram $out/sbin/kpatch \
      --prefix PATH : ${lib.makeBinPath [
        kmod
        binutils
        util-linux
        coreutils
        bash
      ]}
  '';

  meta = with lib; {
    description = "Linux kernel live patching runtime utility";
    homepage = "https://github.com/dynup/kpatch";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
    maintainers = [];
  };
}
