{
  pkgs,
  lib,
  piper-voice ? pkgs.piper-voice-jenny-dioco,
  ...
}:
pkgs.writeShellApplication {
  name = "tts-talk";

  runtimeInputs = with pkgs; [
    piper-tts
    sox
  ];

  text = ''
    MODEL="${piper-voice}/share/piper-voices/en_GB-jenny_dioco-medium.onnx"

    speak() {
      echo "$1" | piper --model "$MODEL" --output-raw 2>/dev/null | play -q -r 22050 -e signed -b 16 -c 1 -t raw - 2>/dev/null
    }

    if [ -n "''${1:-}" ]; then
      speak "$*"
    elif [ ! -t 0 ]; then
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        speak "$line"
      done
    else
      bind 'set editing-mode vi'
      echo "Type what you want to say, press Enter to speak. Ctrl+C to quit."
      echo "(readline vi mode enabled)"
      echo ""
      while IFS= read -erp "> " line; do
        [ -z "$line" ] && continue
        speak "$line"
      done
    fi
  '';

  meta = {
    description = "Interactive text-to-speech using Piper with a British English female voice";
    mainProgram = "tts-talk";
  };
}
