{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  gamescope,
  perl,
  jq,
  wlr-randr,
}:

stdenvNoCC.mkDerivation rec {
  pname = "scopebuddy";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "OpenGamingCollective";
    repo = "ScopeBuddy";
    rev = version;
    hash = "sha256-1n1lZidbtDV9Lm8QKd1s35bOS6Uh8sI3KtBJZ+FwdxQ=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  patches = [ ./fix-ld-preload-leak.patch ];

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/scopebuddy $out/bin/scopebuddy
    ln -s $out/bin/scopebuddy $out/bin/scb

    wrapProgram $out/bin/scopebuddy \
      --prefix PATH : ${lib.makeBinPath [ gamescope perl jq wlr-randr ]}

    runHook postInstall
  '';

  meta = {
    description = "Manager script to make gamescope easier to use on desktop";
    homepage = "https://github.com/OpenGamingCollective/ScopeBuddy";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "scopebuddy";
  };
}
