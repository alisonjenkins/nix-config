{
  pkgs,
  lib,
  piper-voice ? pkgs.piper-voice-jenny-dioco,
  ...
}:
let
  viInputrc = pkgs.writeText "tts-talk-inputrc" ''
    set editing-mode vi
    set show-mode-in-prompt on
    set vi-cmd-mode-string "(cmd) "
    set vi-ins-mode-string "(ins) "
  '';
in
pkgs.writeShellApplication {
  name = "tts-talk";

  runtimeInputs = with pkgs; [
    piper-tts
    rlwrap
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
      # Re-exec under rlwrap for readline vi-mode support if not already wrapped
      if [ -z "''${RLWRAP_RUNNING:-}" ]; then
        export RLWRAP_RUNNING=1
        export INPUTRC="${viInputrc}"
        exec rlwrap -a -pGreen -S "> " "$0"
      fi

      echo "Type what you want to say, press Enter to speak. Ctrl+C to quit."
      echo "(readline vi mode enabled)"
      echo ""
      while IFS= read -r line; do
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
