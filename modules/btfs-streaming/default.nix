{ config, lib, pkgs, ... }:
let
  cfg = config.modules.btfsStreaming;

  btfsManagerScript = pkgs.writeShellScriptBin "btfs-manager" ''
    set -euo pipefail

    REGISTRY="${cfg.registryPath}"
    MOUNT_ROOT="${cfg.mountRoot}"
    CACHE_DIR="${cfg.cacheDir}"

    ensure_registry() {
      if [ ! -f "$REGISTRY" ]; then
        echo '{"mounts":[]}' > "$REGISTRY"
      fi
    }

    cmd_add() {
      local magnet="$1"
      local mount_name="$2"
      local source="''${3:-manual}"

      ensure_registry

      local torrent_hash
      torrent_hash=$(echo "$magnet" | ${pkgs.gnugrep}/bin/grep -oP '(?<=btih:)[a-fA-F0-9]+' | tr '[:upper:]' '[:lower:]')

      if [ -z "$torrent_hash" ]; then
        echo "Error: Could not extract torrent hash from magnet link" >&2
        exit 1
      fi

      # Check if already registered
      if ${pkgs.jq}/bin/jq -e ".mounts[] | select(.torrent_hash == \"$torrent_hash\")" "$REGISTRY" > /dev/null 2>&1; then
        echo "Torrent $torrent_hash already registered"
        return 0
      fi

      local mount_path="$MOUNT_ROOT/$mount_name"
      local cache_path="$CACHE_DIR/$torrent_hash"
      mkdir -p "$mount_path" "$cache_path"

      # Start the BTFS mount via systemd
      systemctl start "btfs-mount@$torrent_hash.service"

      # Register in the persistent registry
      local now
      now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      local tmp
      tmp=$(mktemp)
      ${pkgs.jq}/bin/jq \
        --arg magnet "$magnet" \
        --arg mount_path "$mount_path" \
        --arg cache_path "$cache_path" \
        --arg added_date "$now" \
        --arg source "$source" \
        --arg torrent_hash "$torrent_hash" \
        --arg mount_name "$mount_name" \
        '.mounts += [{
          magnet: $magnet,
          mount_path: $mount_path,
          cache_path: $cache_path,
          added_date: $added_date,
          source: $source,
          torrent_hash: $torrent_hash,
          mount_name: $mount_name
        }]' "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"

      echo "Added and mounted: $mount_name ($torrent_hash)"
    }

    cmd_remove() {
      local hash="$1"

      ensure_registry

      # Stop the BTFS mount
      systemctl stop "btfs-mount@$hash.service" 2>/dev/null || true

      # Get mount path before removing from registry
      local mount_path
      mount_path=$(${pkgs.jq}/bin/jq -r ".mounts[] | select(.torrent_hash == \"$hash\") | .mount_path" "$REGISTRY")

      # Unmount if still mounted
      if [ -n "$mount_path" ] && mountpoint -q "$mount_path" 2>/dev/null; then
        fusermount -uz "$mount_path" 2>/dev/null || true
      fi

      # Clean up directories
      local cache_path="$CACHE_DIR/$hash"
      rm -rf "$cache_path"
      if [ -n "$mount_path" ] && [ -d "$mount_path" ]; then
        rmdir "$mount_path" 2>/dev/null || true
      fi

      # Remove from registry
      local tmp
      tmp=$(mktemp)
      ${pkgs.jq}/bin/jq "del(.mounts[] | select(.torrent_hash == \"$hash\"))" "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"

      echo "Removed: $hash"
    }

    cmd_list() {
      ensure_registry
      ${pkgs.jq}/bin/jq -r '.mounts[] | "\(.torrent_hash)\t\(.mount_name)\t\(.source)\t\(.added_date)"' "$REGISTRY" | \
        column -t -s $'\t' -N "HASH,NAME,SOURCE,ADDED"
    }

    cmd_status() {
      ensure_registry
      local count
      count=$(${pkgs.jq}/bin/jq '.mounts | length' "$REGISTRY")
      echo "Registered mounts: $count"

      local cache_size="0"
      if [ -d "$CACHE_DIR" ]; then
        cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
      fi
      echo "Cache size: $cache_size"

      # Check which mounts are actually active
      local active=0
      for hash in $(${pkgs.jq}/bin/jq -r '.mounts[].torrent_hash' "$REGISTRY"); do
        if systemctl is-active "btfs-mount@$hash.service" > /dev/null 2>&1; then
          active=$((active + 1))
        fi
      done
      echo "Active mounts: $active/$count"
    }

    cmd_evict_cache() {
      local days="''${1:-${toString cfg.cacheEvictionDays}}"
      echo "Evicting cache entries not accessed in $days days..."

      ensure_registry

      local evicted=0
      for hash_dir in "$CACHE_DIR"/*/; do
        [ -d "$hash_dir" ] || continue
        local hash
        hash=$(basename "$hash_dir")

        # Check if any file in the cache was accessed recently
        local recent
        recent=$(find "$hash_dir" -type f -atime "-$days" -print -quit 2>/dev/null)

        if [ -z "$recent" ]; then
          echo "Evicting cache for $hash (no access in $days days)"
          # Only remove cached pieces, not the mount
          find "$hash_dir" -type f -delete 2>/dev/null || true
          evicted=$((evicted + 1))
        fi
      done

      echo "Evicted cache for $evicted torrents"
    }

    case "''${1:-}" in
      add)
        if [ $# -lt 3 ]; then
          echo "Usage: btfs-manager add <magnet-link> <mount-name> [source]" >&2
          exit 1
        fi
        cmd_add "$2" "$3" "''${4:-manual}"
        ;;
      remove)
        if [ $# -lt 2 ]; then
          echo "Usage: btfs-manager remove <torrent-hash>" >&2
          exit 1
        fi
        cmd_remove "$2"
        ;;
      list)
        cmd_list
        ;;
      status)
        cmd_status
        ;;
      evict-cache)
        cmd_evict_cache "''${2:-}"
        ;;
      *)
        echo "Usage: btfs-manager {add|remove|list|status|evict-cache}" >&2
        echo "" >&2
        echo "Commands:" >&2
        echo "  add <magnet-link> <mount-name> [source]  Mount a torrent via BTFS" >&2
        echo "  remove <torrent-hash>                     Unmount and deregister a torrent" >&2
        echo "  list                                      List registered mounts" >&2
        echo "  status                                    Show overall status" >&2
        echo "  evict-cache [days]                        Clear piece cache for stale content" >&2
        exit 1
        ;;
    esac
  '';

  btfsRestoreScript = pkgs.writeShellScriptBin "btfs-restore-mounts" ''
    set -euo pipefail

    REGISTRY="${cfg.registryPath}"

    if [ ! -f "$REGISTRY" ]; then
      echo "No registry found, nothing to restore"
      exit 0
    fi

    count=$(${pkgs.jq}/bin/jq '.mounts | length' "$REGISTRY")
    echo "Restoring $count BTFS mounts..."

    for hash in $(${pkgs.jq}/bin/jq -r '.mounts[].torrent_hash' "$REGISTRY"); do
      mount_path=$(${pkgs.jq}/bin/jq -r ".mounts[] | select(.torrent_hash == \"$hash\") | .mount_path" "$REGISTRY")

      # Ensure mount directory exists
      mkdir -p "$mount_path"

      if systemctl is-active "btfs-mount@$hash.service" > /dev/null 2>&1; then
        echo "Already active: $hash"
      else
        echo "Starting: $hash -> $mount_path"
        systemctl start "btfs-mount@$hash.service" || echo "Warning: Failed to start mount for $hash"
      fi
    done

    echo "Mount restoration complete"
  '';
in
{
  options.modules.btfsStreaming = {
    enable = lib.mkEnableOption "BTFS torrent streaming via FUSE";

    mountRoot = lib.mkOption {
      type = lib.types.path;
      default = "/media/btfs-streaming";
      description = "Base directory for BTFS FUSE mounts.";
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/btfs-cache";
      description = "Directory where BTFS stores downloaded pieces.";
    };

    registryPath = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/btfs-streaming/registry.json";
      description = "Path to the persistent mount registry file.";
    };

    maxCacheSizeGB = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Maximum cache size in GB. null for unlimited.";
    };

    cacheEvictionDays = lib.mkOption {
      type = lib.types.int;
      default = 14;
      description = "Clear piece cache for content not accessed in this many days. Mounts stay active.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.btfs
      pkgs.fuse
      btfsManagerScript
    ];

    # Ensure FUSE is available
    boot.kernelModules = [ "fuse" ];

    # Create required directories
    systemd.tmpfiles.rules = [
      "d ${cfg.mountRoot} 0755 root root -"
      "d ${cfg.cacheDir} 0755 root root -"
      "d ${builtins.dirOf cfg.registryPath} 0755 root root -"
    ];

    # Template service for individual BTFS mounts
    # Instance name (%i) is the torrent hash
    systemd.services."btfs-mount@" = {
      description = "BTFS mount for torrent %i";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";

        # Read mount path and magnet from registry
        ExecStartPre = pkgs.writeShellScript "btfs-mount-pre" ''
          set -euo pipefail
          HASH="%i"
          REGISTRY="${cfg.registryPath}"

          if [ ! -f "$REGISTRY" ]; then
            echo "Registry not found" >&2
            exit 1
          fi

          MOUNT_PATH=$(${pkgs.jq}/bin/jq -r ".mounts[] | select(.torrent_hash == \"$HASH\") | .mount_path" "$REGISTRY")
          if [ -z "$MOUNT_PATH" ] || [ "$MOUNT_PATH" = "null" ]; then
            echo "Torrent $HASH not found in registry" >&2
            exit 1
          fi

          mkdir -p "$MOUNT_PATH"
          mkdir -p "${cfg.cacheDir}/$HASH"
        '';

        ExecStart = pkgs.writeShellScript "btfs-mount-start" ''
          set -euo pipefail
          HASH="%i"
          REGISTRY="${cfg.registryPath}"

          MAGNET=$(${pkgs.jq}/bin/jq -r ".mounts[] | select(.torrent_hash == \"$HASH\") | .magnet" "$REGISTRY")
          MOUNT_PATH=$(${pkgs.jq}/bin/jq -r ".mounts[] | select(.torrent_hash == \"$HASH\") | .mount_path" "$REGISTRY")

          exec ${pkgs.btfs}/bin/btfs \
            --keep \
            -o allow_other \
            -o big_writes \
            "$MAGNET" \
            "$MOUNT_PATH"
        '';

        ExecStop = pkgs.writeShellScript "btfs-mount-stop" ''
          HASH="%i"
          REGISTRY="${cfg.registryPath}"
          MOUNT_PATH=$(${pkgs.jq}/bin/jq -r ".mounts[] | select(.torrent_hash == \"$HASH\") | .mount_path" "$REGISTRY")
          ${pkgs.fuse}/bin/fusermount -uz "$MOUNT_PATH" 2>/dev/null || true
        '';

        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStopSec = "30s";
      };
    };

    # Boot-time service to restore all registered mounts
    systemd.services.btfs-restore = {
      description = "Restore BTFS mounts from registry";
      after = [ "network-online.target" "local-fs.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${btfsRestoreScript}/bin/btfs-restore-mounts";
      };
    };

    # Cache eviction timer
    systemd.timers.btfs-cache-eviction = {
      description = "BTFS cache eviction timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.services.btfs-cache-eviction = {
      description = "Evict stale BTFS cache entries";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${btfsManagerScript}/bin/btfs-manager evict-cache";
      };
    };
  };
}
