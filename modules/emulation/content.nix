# modules/emulation/content.nix
#
# Declarative, manifest-driven content sync for ROMs / BIOS / firmware /
# Switch keys — see design/02-content-sync.md.
#
# Model (from the design doc): the Nix config enumerates EXACTLY which files
# should exist per "set"; an `rclone` pass against a private Backblaze B2
# bucket makes each set's `dest` match that list exactly — fetch what's
# listed, prune anything that isn't. B2 is just the byte store; the Nix
# `files` list is the source of truth. This keeps multi-GB private dumps OUT
# of the nix store (and therefore out of the niks3 cache push) while staying
# version-controlled + reproducible at the *management* layer.
#
# Nothing copyrighted ever touches /nix/store. We render only:
#   - a small text manifest per set (a list of filenames), and
#   - systemd user units that drive `rclone`.
# The bytes land on the persisted /home disk (this host bind-mounts /home to
# /persistence/home, so synced content survives the impermanence wipe with no
# extra config).
#
# Credentials never enter the store either: a sops-nix *template* renders an
# rclone env file (RCLONE_CONFIG_<REMOTE>_ACCOUNT / _KEY) owned by the user,
# mode 0400, and the user services load it via EnvironmentFile.
#
# LEGAL: ROMs, BIOS, prod.keys/title.keys and firmware are the user's legal
# responsibility — own-console / own-disc dumps ONLY. This module ships no
# copyrighted bytes; it only stores a manifest of filenames + B2 object paths.
{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.emulation;
  ccfg = cfg.content;
  catalogue = import ./catalogue.nix;

  # Per-console ROM sync sets derived from the consoles model (default.nix). Each
  # ENABLED console contributes a set fetching exactly its `games` into
  # ~/Emulation/roms/<romDir>; a DISABLED console that still lists games gets an
  # empty-allowlist set so its ROMs are PRUNED off disk (the single console
  # toggle removes its games too). Consoles that are off AND list no games are
  # skipped (nothing to fetch or prune).
  consoleRomSets = lib.listToAttrs (lib.filter (x: x != null) (lib.mapAttrsToList
    (name: c:
      let cons = catalogue.${name}; in
      if (c.enable || c.games != [ ]) then
        lib.nameValuePair "roms-${name}" {
          bucketPrefix = "roms/${cons.romDir}";
          dest = "~/Emulation/roms/${cons.romDir}";
          perms = "0755";
          files = if c.enable then c.games else [ ];
          symlinkInto = [ ];
        }
      else null)
    cfg.consoles));

  # Effective sets = the manual content.sets (bios/keys/firmware) + the derived
  # per-console ROM sets. Everything below (manifests, units, prune, symlinks)
  # operates on this merged map.
  allSets = ccfg.sets // consoleRomSets;

  # rclone reads RCLONE_CONFIG_<REMOTE>_* from the environment, so the remote
  # name has to be upper-cased for the variable names. The set of secrets the
  # sops template interpolates is keyed off `keySopsSecret` (see below).
  remoteEnv = lib.toUpper ccfg.remote;

  # The sops template that materialises the rclone env file. Declared as a
  # NixOS-level secret/template; the rendered file is owned by cfg.user 0400.
  # The path is stable + predictable so the user units can name it directly.
  envFile = config.sops.templates."emulation-rclone-env".path;

  # Two sops secrets carry the B2 native-app-key pair. We derive both names
  # from the single `keySopsSecret` option so the host only has to point at one
  # logical secret group (e.g. keySopsSecret = "backblaze/emulation" →
  # "backblaze/emulation/accountId" + "backblaze/emulation/applicationKey").
  accountSecretName = "${ccfg.keySopsSecret}/accountId";
  appKeySecretName = "${ccfg.keySopsSecret}/applicationKey";

  # Expand a HOME-relative path ("~/Emulation/roms" or "Emulation/roms") to an
  # absolute one under the user's home. The user services run as the user, so
  # `~` would resolve — but we expand here so the prune logic (and the
  # activation symlinks) have an unambiguous absolute target to reason about.
  homeDir = config.home-manager.users.${cfg.user}.home.homeDirectory;
  expandHome = p:
    if lib.hasPrefix "~/" p then "${homeDir}/${lib.removePrefix "~/" p}"
    else if lib.hasPrefix "/" p then p
    else "${homeDir}/${p}";

  # Per-set rendered manifest: one filename per line, exactly the `files` list.
  # `rclone copy --files-from <manifest>` fetches only these; the explicit
  # prune pass below deletes anything in `dest` that isn't on this list. Pure
  # text → fine in the store; the ROMs themselves never enter it.
  manifestFor = name: set:
    pkgs.writeText "emulation-manifest-${name}" (
      lib.concatStringsSep "\n" set.files + "\n"
    );

  # Single-set sync: copy listed files, then prune everything else under dest.
  #
  # Prune is implemented as an explicit pass (NOT `rclone sync
  # --delete-excluded`) for predictability — the design doc prefers this
  # because the delete is provably scoped to *this set's* dest: we list the
  # files currently present under dest, subtract the manifest, and delete only
  # the remainder. It can never wander into saves/configs/other dirs.
  syncSetScript = name: set:
    let
      dest = expandHome set.dest;
      manifest = manifestFor name set;
      remotePath = "${ccfg.remote}:${ccfg.bucket}/${set.bucketPrefix}";
      # Directory mode for the dest tree (0700 for keys/firmware, 0755 default).
      destMode = set.perms;
    in ''
      set -euo pipefail

      dest=${lib.escapeShellArg dest}
      manifest=${manifest}

      echo "[emulation-sync:${name}] dest=$dest remote=${remotePath}"

      # Ensure the dest tree exists with the requested perms before syncing.
      mkdir -p "$dest"
      chmod ${destMode} "$dest"

      # 1) Fetch only the listed files. Incremental: rclone skips unchanged
      #    files via size + (with --checksum) hash. --files-from restricts the
      #    transfer set to exactly the manifest, relative to the remote prefix.
      rclone copy \
        --config /dev/null \
        --files-from "$manifest" \
        --checksum \
        --transfers 4 \
        --create-empty-src-dirs=false \
        ${remotePath} "$dest"

      # 2) Prune anything under dest that is NOT in the manifest. We build the
      #    allowlist as a sorted, NUL-delimited set of dest-relative paths and
      #    walk the actual files under dest, deleting the complement. Scoped
      #    strictly to "$dest" — never touches sibling dirs.
      allow="$(mktemp)"
      have="$(mktemp)"
      trap 'rm -f "$allow" "$have"' EXIT

      # Manifest entries are dest-relative already (they mirror the bucket
      # prefix layout). Normalise + sort for comm(1).
      LC_ALL=C sort -u "$manifest" > "$allow"

      # Enumerate files actually present, as dest-relative paths.
      ( cd "$dest" && find . -type f -printf '%P\n' ) | LC_ALL=C sort -u > "$have"

      # Lines present on disk but absent from the manifest → delete them.
      LC_ALL=C comm -13 "$allow" "$have" | while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        echo "[emulation-sync:${name}] prune: $rel"
        rm -f -- "$dest/$rel"
      done

      # Drop any now-empty subdirectories left behind by pruning (but keep the
      # set root itself).
      find "$dest" -mindepth 1 -type d -empty -delete || true

      # Re-assert perms on the (now reconciled) tree. Keys/firmware sets want
      # 0700 dirs; files inherit the same restriction for the secret sets.
      chmod -R ${destMode} "$dest" || true
    '';

  # Per-set executable sync script (used by both the systemd unit and the
  # rom-sync wrapper, so the two paths stay byte-identical).
  syncSetExe = name: set:
    pkgs.writeShellScript "emulation-sync-${name}" (syncSetScript name set);

  # The on-demand wrapper: `rom-sync [set...]`. With no args it runs every
  # configured set; with args it runs only the named sets. Loads the same
  # rclone env file the systemd units use, so a user can run it from a shell.
  romSync = pkgs.writeShellApplication {
    name = "rom-sync";
    runtimeInputs = [ pkgs.rclone pkgs.coreutils pkgs.findutils ];
    text = ''
      # Manual content sync (mirror of the emulation-sync-<set> user units).
      # Usage: rom-sync [set-name ...]   (no args = all sets)
      if [ -r ${lib.escapeShellArg envFile} ]; then
        set -a
        # shellcheck disable=SC1090,SC1091
        . ${lib.escapeShellArg envFile}
        set +a
      else
        echo "rom-sync: rclone env file not found at ${envFile}" >&2
        echo "          (sops secret '${ccfg.keySopsSecret}' not provisioned?)" >&2
        exit 1
      fi

      run_set() {
        case "$1" in
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: set:
        "        ${name}) ${syncSetExe name set} ;;"
      ) allSets)}
          *) echo "rom-sync: unknown set '$1'" >&2; return 1 ;;
        esac
      }

      if [ "$#" -eq 0 ]; then
        for s in ${lib.concatStringsSep " " (lib.attrNames allSets)}; do
          run_set "$s"
        done
      else
        for s in "$@"; do run_set "$s"; done
      fi
    '';
  };

  # systemd user service definition for a single set.
  serviceFor = name: set: {
    "emulation-sync-${name}" = {
      Unit = {
        Description = "Emulation content sync (${name}) — rclone copy+prune from B2";
        # Best-effort: don't fail the graphical session if the network or the
        # creds aren't ready yet; the timer will retry.
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        # The sops template renders to a user-owned 0400 file; load the B2
        # creds from it so no secret ever lands in the unit text or the store.
        EnvironmentFile = envFile;
        ExecStart = syncSetExe name set;
        # Network sync — be patient but bounded.
        TimeoutStartSec = "30min";
      };
      # Sync on login so a fresh session reconciles content without waiting for
      # the timer. NOT in the activation script — we never want a
      # network-blocking rebuild (a removed item is pruned on the next sync run,
      # not instantly at `just switch`).
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };

  # systemd user timer definition for a single set.
  timerFor = name: _set: {
    "emulation-sync-${name}" = {
      Unit.Description = "Schedule emulation content sync (${name})";
      Timer = {
        OnCalendar = ccfg.schedule;
        Persistent = true;
        # Light jitter so multiple sets don't all hammer B2 at once.
        RandomizedDelaySec = "2min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };

  # home.activation symlinks: for each set, link the synced dest (or specific
  # files within it) into the per-emulator dirs each emulator expects to find
  # BIOS / keys / firmware in. We symlink the whole `dest` directory contents
  # into each target so adding a file to the manifest automatically surfaces it
  # in every emulator path on the next sync (no rebuild needed).
  #
  # These run as the user during home-manager activation. They are idempotent
  # and tolerate the dest not existing yet (first boot before the first sync):
  # the symlink target dir is created, but if the source files aren't there yet
  # the emulator simply sees an empty/again-populated dir after the sync runs.
  symlinkActivationFor = name: set:
    let
      dest = expandHome set.dest;
    in
      lib.optionalAttrs (set.symlinkInto != [ ]) {
        "emulationSymlink-${name}" = lib.hm.dag.entryAfter [ "writeBoundary" ] (
          lib.concatMapStringsSep "\n" (rawTarget:
            let target = expandHome rawTarget;
            in ''
              # Link synced ${name} content into ${target}
              run mkdir -p ${lib.escapeShellArg target}
              # Symlink each top-level entry of the set's dest into the target
              # dir (so the emulator sees real filenames, not a nested dir).
              if [ -d ${lib.escapeShellArg dest} ]; then
                for src in ${lib.escapeShellArg dest}/*; do
                  [ -e "$src" ] || continue
                  run ln -sfn "$src" ${lib.escapeShellArg target}/"$(basename "$src")"
                done
              fi
            ''
          ) set.symlinkInto
        );
      };
in
{
  # Pull in sops-nix so the `sops.secrets` / `sops.templates` options below are
  # always declared, regardless of whether the host imports sops-nix itself.
  # This only DECLARES the option tree (and the sops-nix activation machinery
  # that no-ops without any secrets) — it ships no secret and needs no decrypted
  # file at eval time. Without it, referencing an undeclared `sops` option in
  # the config block throws even when content.enable = false (NixOS reports
  # undeclared-option definitions before applying the mkIf guard).
  imports = [ inputs.sops-nix.nixosModules.sops ];

  options.modules.emulation.content = {
    enable = lib.mkEnableOption "B2 manifest-driven content sync (ROMs/BIOS/firmware/keys)";

    remote = lib.mkOption {
      type = lib.types.str;
      default = "b2";
      description = ''
        rclone remote name. Drives both the `<remote>:<bucket>` path and the
        RCLONE_CONFIG_<REMOTE>_* environment variable names rendered by the
        sops template. Native B2 (type = b2) is simplest; an S3-compatible
        key works too if the template is adjusted to type = s3.
      '';
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "B2 bucket holding the private content (e.g. \"ali-emulation\").";
    };

    keySopsSecret = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Logical sops secret group holding the B2 native application key.
        The module references two leaf secrets derived from this name:
        `<keySopsSecret>/accountId` (the B2 keyID) and
        `<keySopsSecret>/applicationKey` (the B2 appKey). Both are rendered
        into a user-owned 0400 rclone env file via a sops template — creds
        NEVER enter the nix store.

        See `sopsFile` below for where the encrypted values are read from at
        activation. This module evaluates fine without the decrypted secret
        present at eval time; sops-nix only needs it at activation.
      '';
    };

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Encrypted sops file holding the two B2 leaf secrets
        (`<keySopsSecret>/accountId` + `<keySopsSecret>/applicationKey`). When
        null (the default) the host's `sops.defaultSopsFile` is used instead.
        The file only needs to exist at activation time, not at eval — point
        this at e.g. `self + "/secrets/ali-steam-deck/emulation.enc.yaml"`.
      '';
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = ''
        systemd OnCalendar expression for the per-set sync timers
        (e.g. "daily", "hourly", "*-*-* 04:00:00"). Sync also runs on login
        via graphical-session.target.
      '';
    };

    sets = lib.mkOption {
      default = { };
      description = ''
        Named content sets. Each set is an EXPLICIT allowlist of files under a
        bucket prefix, synced to a HOME-relative dest, with the dest reconciled
        to match the list exactly (listed = present, unlisted = pruned).
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          bucketPrefix = lib.mkOption {
            type = lib.types.str;
            description = "Object-name prefix within the bucket (e.g. \"roms\", \"switch/keys\").";
          };
          dest = lib.mkOption {
            type = lib.types.str;
            description = "HOME-relative destination dir (e.g. \"~/Emulation/roms\").";
          };
          perms = lib.mkOption {
            type = lib.types.str;
            default = "0755";
            description = "Directory mode for the dest tree (\"0700\" for keys/firmware).";
          };
          files = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              EXPLICIT allowlist of object paths (relative to bucketPrefix /
              dest). Exactly these are fetched; anything else under dest is
              pruned on each sync. The target dir is a pure function of this
              list.
            '';
          };
          symlinkInto = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              HOME-relative per-emulator dirs to symlink this set's contents
              into (e.g. RetroArch system dir, citron keys dir). Wired via
              home-manager home.activation, idempotent + impermanence-safe.
            '';
          };
        };
      });
    };
  };

  config = lib.mkIf (cfg.enable && ccfg.enable) {
    # --- Credentials: sops template → user-owned 0400 rclone env file ---------
    #
    # We declare the two leaf secrets by NAME only (no inline sopsFile), so the
    # module evaluates even when the encrypted file doesn't exist yet — the
    # host supplies sops.defaultSopsFile. sops-nix reads the file at activation,
    # not at eval.
    sops.secrets.${accountSecretName} = {
      owner = cfg.user;
      mode = "0400";
    } // lib.optionalAttrs (ccfg.sopsFile != null) { sopsFile = ccfg.sopsFile; };
    sops.secrets.${appKeySecretName} = {
      owner = cfg.user;
      mode = "0400";
    } // lib.optionalAttrs (ccfg.sopsFile != null) { sopsFile = ccfg.sopsFile; };

    # The template interpolates the two placeholders into an rclone env file.
    # rclone reads RCLONE_CONFIG_<REMOTE>_* from the process environment, so no
    # rclone.conf and no creds in /nix/store. Owned by the user, 0400.
    sops.templates."emulation-rclone-env" = {
      owner = cfg.user;
      mode = "0400";
      content = ''
        RCLONE_CONFIG_${remoteEnv}_TYPE=b2
        RCLONE_CONFIG_${remoteEnv}_ACCOUNT=${config.sops.placeholder.${accountSecretName}}
        RCLONE_CONFIG_${remoteEnv}_KEY=${config.sops.placeholder.${appKeySecretName}}
      '';
    };

    # --- User-level wiring (home-manager-as-NixOS-module) ---------------------
    #
    # All of this MUST live under home-manager.users.<user> so `~` resolves and
    # the units run in the graphical user session (not the system manager).
    home-manager.users.${cfg.user} = {
      # On-demand wrapper for manual runs.
      home.packages = [ romSync ];

      # rclone must be on the user PATH for the units' ExecStart shell scripts
      # (writeShellScript doesn't pin runtimeInputs). Pin it explicitly so the
      # services don't depend on ambient PATH.
      systemd.user.services =
        lib.mkMerge (lib.mapAttrsToList (name: set:
          lib.mapAttrs (_n: svc:
            lib.recursiveUpdate svc {
              Service.Environment = [
                "PATH=${lib.makeBinPath [ pkgs.rclone pkgs.coreutils pkgs.findutils ]}"
              ];
            }
          ) (serviceFor name set)
        ) allSets);

      systemd.user.timers =
        lib.mkMerge (lib.mapAttrsToList timerFor allSets);

      # BIOS / keys / firmware placement: symlink each set's synced dest into
      # the dirs each emulator expects (RetroArch system dir, PCSX2 bios,
      # citron/eden keys + nand, Ryujinx system, ...).
      home.activation =
        lib.mkMerge (lib.mapAttrsToList symlinkActivationFor allSets);
    };
  };
}
