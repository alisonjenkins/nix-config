# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{pkgs, ...}: rec {
  # example = pkgs.callPackage ./example { };
  git-clean = pkgs.callPackage ./git-clean { inherit pkgs; };
  hm-backup-file = pkgs.callPackage ./hm-backup-file { inherit pkgs; };
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
  spec-kit = pkgs.callPackage ./spec-kit {};
  citron = pkgs.callPackage ./citron {};
  eden = pkgs.callPackage ./eden {};
  obscura = pkgs.callPackage ./obscura {};
  camoufox-browser = pkgs.callPackage ./camoufox-browser {};
  create-sky-colonies-server = pkgs.callPackage ./create-sky-colonies-server {};
  minecraft-modpack-tools = pkgs.callPackage ./minecraft-modpack-tools {};
  create-arkana-aeronautics-server = pkgs.callPackage ./create-arkana-aeronautics-server {
    minecraft-modpack-tools = pkgs.callPackage ./minecraft-modpack-tools {};
  };
  create-arkana-aeronautics-client = pkgs.callPackage ./create-arkana-aeronautics-client {};
  nbt-studio = pkgs.callPackage ./nbt-studio {};
  scopebuddy = pkgs.callPackage ./scopebuddy {};
  pup = pkgs.callPackage ./pup {};
  pup-claude = pkgs.callPackage ./pup-claude {};
  llama-models = pkgs.callPackage ./llama-models {};
  superpowers = pkgs.callPackage ./superpowers {};
  token-savior = pkgs.callPackage ./token-savior { python3Packages = pkgs.unstable.python3Packages; };
  claude-statusbar = pkgs.callPackage ./claude-statusbar {
    python3Packages = pkgs.unstable.python3Packages;
    claude-monitor = pkgs.unstable.claude-monitor;
  };
  # Built for whichever platform the package set is instantiated for, so
  # pkgsi686Linux.steam-display-filter gives the 32-bit build the Steam client
  # needs. See the package for why it exists.
  steam-display-filter = pkgs.callPackage ./steam-display-filter { };
  # Both ABIs of the display filter under one prefix, laid out for glibc's $LIB
  # token. Steam is a 32-bit client that spawns 64-bit helpers, and a
  # single-ABI LD_PRELOAD makes every process of the other ABI print "wrong ELF
  # class" before ignoring it; "…/$LIB/libsteam-display-filter.so" lets the
  # loader pick lib or lib64 per process instead.
  #
  # Defined unconditionally on purpose. This file is applied as an overlay to
  # every package set including pkgsi686Linux, and guarding the attribute on
  # `pkgs.stdenv.hostPlatform` would make the overlay's attribute *names*
  # depend on pkgs, which cannot be built until those names are known —
  # infinite recursion. The reference to pkgsi686Linux below is only in the
  # value, which stays lazy and is never forced from the 32-bit set.
  steam-display-filter-multiarch =
    pkgs.runCommand "steam-display-filter-multiarch"
      { meta.description = "steam-display-filter for both ABIs, laid out for \$LIB"; }
      ''
        mkdir -p $out/lib $out/lib64
        ln -s ${pkgs.pkgsi686Linux.steam-display-filter}/lib/libsteam-display-filter.so $out/lib/
        ln -s ${pkgs.steam-display-filter}/lib/libsteam-display-filter.so $out/lib64/
      '';
}
