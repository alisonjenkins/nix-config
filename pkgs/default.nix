# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{pkgs, ...}: rec {
  # example = pkgs.callPackage ./example { };
  git-clean = pkgs.callPackage ./git-clean { inherit pkgs; };
  kpatch = pkgs.callPackage ./kpatch {};
  lock-session = pkgs.callPackage ./lock-session { inherit pkgs; };
  nix-flake-template-init = pkgs.callPackage ./nix-flake-template-init {} ;
  suspendScripts = pkgs.callPackage ./suspend-scripts {};
  wallpapers = pkgs.callPackage ./wallpapers {};
  firefox-addons = pkgs.callPackage ./firefox-addons {};
  detect-location = pkgs.callPackage ./detect-location { inherit pkgs; };
  audio-context-volume = pkgs.callPackage ./audio-context-volume { inherit pkgs; };
  bluetooth-connect = pkgs.callPackage ./bluetooth-connect { inherit pkgs; };
  btfs-bridge = pkgs.callPackage ./btfs-bridge { inherit pkgs; };
  tiny4linux = pkgs.callPackage ./tiny4linux { inherit pkgs; };
  tiny4linux-gui = pkgs.callPackage ./tiny4linux { inherit pkgs; withCli = false; };
  tiny4linux-cli = pkgs.callPackage ./tiny4linux { inherit pkgs; withGui = false; };
  lucien = pkgs.callPackage ./lucien {};
  uresourced = pkgs.callPackage ./uresourced {};
  xr-video-player = pkgs.callPackage ./xr-video-player {};
  piper-voice-jenny-dioco = pkgs.callPackage ./piper-voice-jenny-dioco {};
  piper-tts-talk = pkgs.callPackage ./piper-tts-talk { inherit pkgs; piper-voice = piper-voice-jenny-dioco; };
  caveman = pkgs.callPackage ./caveman {};
  cavekit = pkgs.callPackage ./cavekit {};
  cavemem = pkgs.callPackage ./cavemem {};
}
