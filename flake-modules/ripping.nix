# Optical-disc ripping dev shell (`nix develop .#ripping`).
#
# Redump-grade PS1 ripping for the emulation stack (see modules/emulation +
# CLAUDE.md). dd is the wrong tool for PS1 — discs are multi-track (a data
# track + Red Book CD-DA audio tracks + subchannel), which dd flattens and
# corrupts. `redumper` is the current Redump-standard dumper (multi-pass,
# subchannel, error correction, audio-track aware, emits a verified .cue +
# per-track .bin). `chdman` (shipped inside `mame`) packs the .cue/.bin into a
# single compressed .chd that swanstation / beetle-psx read directly.
#
# Tools are resolved via this shell / the scripts' runtimeInputs — never
# assumed on PATH (repo convention: see memory feedback_script_tooling).
#
# Permissions: redumper needs raw access to the optical drive. The invoking
# user must be in the drive's group (usually `cdrom`); no sudo. If raw reads
# fail on a flaky USB drive, fall back to `cdrdao read-cd --read-raw` then
# `bin2chd`.
{ ... }:
{
  perSystem = { pkgs, ... }:
    let
      # name a disc image Redump-style: "Title (Region)" or, multi-disc,
      # "Title (Region) (Disc N)".
      ripPsx = pkgs.writeShellApplication {
        name = "rip-psx";
        runtimeInputs = with pkgs; [ redumper mame coreutils gnugrep ];
        text = ''
          usage() {
            cat >&2 <<'EOF'
          rip-psx — dump a PS1 disc to a Redump-named .chd

          Usage:
            rip-psx "<Title>" "<Region>" [--disc N] [--drive DEV] [--out DIR]

          Region: USA | Europe | Japan  (UK English releases are "Europe").
          --disc N : multi-disc game; the .chd goes into <out>/discs/ and a line
                     is added to "<out>/<Title> (<Region>).m3u" (the launchable).
          --drive  : optical device (default /dev/sr0).
          --out    : output root, the psx roms dir layout (default ./psx-out, or
                     $EMU_RIP_OUT).

          Examples:
            rip-psx "Final Fantasy VII" Europe --disc 1
            rip-psx "Final Fantasy VII" Japan  --disc 1
            rip-psx "Metal Gear Solid"  Europe          # single disc
          EOF
            exit 2
          }

          [ "$#" -ge 2 ] || usage
          title=$1; region=$2; shift 2
          disc=""; drive=/dev/sr0; out=''${EMU_RIP_OUT:-$PWD/psx-out}
          while [ "$#" -gt 0 ]; do
            case "$1" in
              --disc)  disc=$2;  shift 2 ;;
              --drive) drive=$2; shift 2 ;;
              --out)   out=$2;   shift 2 ;;
              *) echo "unknown arg: $1" >&2; usage ;;
            esac
          done
          [ -n "$title" ] && [ -n "$region" ] || usage
          case "$region" in
            USA|Europe|Japan) ;;
            *) echo "warning: region '$region' is not a Redump tag (USA/Europe/Japan) — scrapers may miss artwork" >&2 ;;
          esac
          [ -b "$drive" ] || echo "warning: $drive is not a block device — is the disc drive connected?" >&2

          if [ -n "$disc" ]; then
            name="$title ($region) (Disc $disc)"
            destdir="$out/discs"
          else
            name="$title ($region)"
            destdir="$out"
          fi
          work="$out/.work/$name"
          mkdir -p "$work" "$destdir"

          echo ">> redumper: dumping '$name' from $drive"
          redumper --verbose --drive="$drive" --image-path="$work" --image-name="$name"

          cue="$work/$name.cue"
          [ -f "$cue" ] || { echo "error: redumper produced no .cue at '$cue'" >&2; exit 1; }

          chd="$destdir/$name.chd"
          echo ">> chdman: $cue -> $chd"
          chdman createcd -i "$cue" -o "$chd"

          if [ -n "$disc" ]; then
            m3u="$out/$title ($region).m3u"
            line="discs/$name.chd"
            grep -qxF "$line" "$m3u" 2>/dev/null || printf '%s\n' "$line" >> "$m3u"
            echo ">> m3u: $m3u"; sort -u "$m3u" -o "$m3u"
          fi

          log="$work/$name.log"
          if [ -f "$log" ]; then
            echo ">> Redump hashes (verify against the Redump DAT):"
            grep -Ei 'md5|sha1|crc' "$log" || true
          fi
          echo ">> done: $chd"
          echo "   (raw .bin/.cue left in '$work' — delete after verifying; then upload the .chd to B2 roms/psx/)"
        '';
      };

      # already have .bin/.cue (or .iso) from another ripper → just pack to .chd.
      bin2chd = pkgs.writeShellApplication {
        name = "bin2chd";
        runtimeInputs = with pkgs; [ mame coreutils ];
        text = ''
          usage() { echo "Usage: bin2chd <game.cue|game.iso> [out.chd]" >&2; exit 2; }
          [ "$#" -ge 1 ] || usage
          in=$1
          [ -f "$in" ] || { echo "error: no such file: $in" >&2; exit 1; }
          out=''${2:-"''${in%.*}.chd"}
          echo ">> chdman createcd: $in -> $out"
          chdman createcd -i "$in" -o "$out"
          echo ">> done: $out"
        '';
      };
    in
    {
      devShells.ripping = pkgs.mkShellNoCC {
        # redumper + mame (for chdman) directly on PATH for manual use; the
        # scripts wrap the common PS1 flows. ps3-disc-dumper is GUI-only (no
        # CLI), so it's PATH-only — no wrapper. ps3netsrv serves a CFW PS3's
        # decrypted dump over the network to the PC (route B).
        packages = (with pkgs; [ redumper mame cdrdao ps3-disc-dumper ps3netsrv ]) ++ [ ripPsx bin2chd ];
        shellHook = ''
          echo "ripping shell"
          echo "  PS1: rip-psx \"<Title>\" <USA|Europe|Japan> [--disc N] [--drive /dev/sr0]"
          echo "       bin2chd <game.cue> [out.chd]   # pack existing bin/cue -> chd"
          echo "  PS3: ps3-disc-dumper                # GUI; auto-fetches IRD, outputs decrypted JB folder for RPCS3"
          echo "       (needs a PS3-compatible Blu-ray drive — see rpcs3.net/quickstart#dumping_drives)"
          echo "       ps3netsrv                      # serve a CFW-PS3 decrypted dump to the PC (route B)"
          echo "  raw tools on PATH: redumper, chdman, cdrdao"
        '';
      };
    };
}
