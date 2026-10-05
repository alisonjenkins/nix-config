{ lib, stdenvNoCC, python3, makeWrapper }:

stdenvNoCC.mkDerivation {
  pname = "vr-foveation-bench";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./vr_foveation_bench ./tests ];
  };

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ python3 ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest discover -s tests -t .
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    site=$out/lib/${python3.libPrefix}/site-packages
    mkdir -p "$site" $out/bin
    cp -r vr_foveation_bench "$site/"
    find "$site" -name __pycache__ -type d -prune -exec rm -rf {} +
    makeWrapper ${lib.getExe python3} $out/bin/vr-foveation-bench \
      --set PYTHONPATH "$site" \
      --add-flags "-m vr_foveation_bench.cli"
    runHook postInstall
  '';

  meta = {
    description = "Measurement tooling for the VR foveated-rendering benchmark (spec 005)";
    mainProgram = "vr-foveation-bench";
    platforms = lib.platforms.unix;
  };
}
