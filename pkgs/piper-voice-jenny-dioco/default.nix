{
  lib,
  fetchurl,
  stdenvNoCC,
}:

let
  model = fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/jenny_dioco/medium/en_GB-jenny_dioco-medium.onnx";
    hash = "sha256-RpxjDSCeE53TkqZr9KveSrhjkKAmnB5HtOXXzoFSawE=";
  };

  config = fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/jenny_dioco/medium/en_GB-jenny_dioco-medium.onnx.json";
    hash = "sha256-qaepOjF8mjy2Vj436wV9+e8JwGGIqKQ0Gw/LWMulTdQ=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "piper-voice-jenny-dioco";
  version = "medium";

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/share/piper-voices
    cp ${model} $out/share/piper-voices/en_GB-jenny_dioco-medium.onnx
    cp ${config} $out/share/piper-voices/en_GB-jenny_dioco-medium.onnx.json
  '';

  meta = with lib; {
    description = "Piper TTS voice model - Jenny DioCo (British English female, medium quality)";
    homepage = "https://huggingface.co/rhasspy/piper-voices";
    license = licenses.free; # Custom attribution license - credit voice as "Jenny (Dioco)"
    platforms = platforms.all;
  };
}
