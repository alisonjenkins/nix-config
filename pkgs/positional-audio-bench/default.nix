{ lib, stdenv, python3Packages, makeWrapper, pipewire }:

python3Packages.buildPythonApplication {
  pname = "positional-audio-bench";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    numpy
    scipy
    h5py
    soundfile
  ];

  nativeCheckInputs = with python3Packages; [ pytestCheckHook ];
  # live.py shells out to pw-cat at runtime; not exercised by the unit suite
  # (no PipeWire session in the build sandbox), so no build-time dependency.
  nativeBuildInputs = [ makeWrapper ];

  # `live-verify` needs pw-cat on PATH, but PipeWire is Linux-only — the
  # offline `tune`/`regress`/`sweep-datasets` commands (and the whole test
  # suite) are plain Python and build fine everywhere, so only wrap PATH
  # where pipewire actually exists rather than making the whole package
  # Linux-only.
  postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
    wrapProgram $out/bin/positional-audio-bench \
      --prefix PATH : ${lib.makeBinPath [ pipewire ]}
  '';

  pythonImportsCheck = [ "positional_audio_bench" ];

  meta = {
    description = "Objective localization benchmark for the binaural 7.1 HRTF chain (modules.desktop.pipewire.binauralSurround)";
    mainProgram = "positional-audio-bench";
    platforms = lib.platforms.all;
  };
}
