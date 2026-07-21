{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
in {
  flake.nixosConfigurations.home-storage-server-1 = lib.nixosSystem {
    specialArgs = {
      username = "ali";
      inherit inputs;
      inherit (self) outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.locale
      self.nixosModules.base
      self.nixosModules.nohang
      self.nixosModules.servers
      self.nixosModules.storage-server
      self.nixosModules.home-storage-server-1-hardware
      self.nixosModules.home-storage-server-1-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops

      # Host-specific configuration
      ({ config, inputs, lib, outputs, pkgs, utils, ... }:
      let
        sambaSettings = config.services.samba.settings;
        shareNames = builtins.filter (name: name != "global") (builtins.attrNames sambaSettings);
        sambaUsers = lib.unique (lib.flatten (map (share:
          builtins.filter (u: u != "") (lib.splitString " " (lib.attrByPath [ "valid users" ] "" sambaSettings.${share}))
        ) shareNames));

        # systemd .mount unit names for every disk that backs the mergerfs pool
        # (the "/media/disks/*" branch glob; parity is excluded — it is not a
        # pool branch). Derived from fileSystems so it auto-tracks disk add/
        # remove with no second list to keep in sync. Consumed by the
        # media-disks-ready barrier below to order the pool mount after them.
        mergerfsBranchMounts = map (mp: "${utils.escapeSystemdPath mp}.mount")
          (builtins.filter (lib.hasPrefix "/media/disks/")
            (builtins.attrNames config.fileSystems));
      in
      {
        modules.nohang = {
          enable = true;
          extraProtectedProcesses = [ "smbd" "nmbd" "nfsd" ];
        };
        modules.base = {
          enable = true;
          enableImpermanence = true;
        };
        modules.locale.enable = true;
        modules.storage-server.enable = true;
        modules.servers = {
          enable = true;
          prometheus.smartctlExporter.enable = true;
          lokiPush.enable = true;
        };

        console.keyMap = "us";
        programs.zsh.enable = true;
        time.timeZone = "Europe/London";

        boot = {
          kernelPackages = pkgs.linuxPackages_latest;
          kernelParams = [
            "irqpoll"
            # Enumerate all SCSI/mpt3sas LUNs synchronously at boot instead of
            # the async default. The LSI HBA presents ~16 disks across 8 SCSI
            # hosts; async scanning let local-fs proceed before every host had
            # finished, so on a cold boot (power loss) the mergerfs pool globbed
            # an EMPTY branch set and came up as a broken pool ("no valid
            # mergerfs branch found") -> NFS answered ENOENT for every subtree
            # (jellyfin/pharos mount failures, 2026-07-20). sync scan makes the
            # disks present before any mount runs. The post-boot
            # scsi-rescan-and-mount service below stays as a fallback for a disk
            # that only spins up later than the kernel scan.
            "scsi_mod.scan=sync"
          ];
          # BFQ is the only in-tree I/O scheduler that honours IOPRIO_CLASS_IDLE
          # and prioritises latency-sensitive readers over a bulk sequential
          # writer -- it is what makes the idle-class snapraid + best-effort smbd
          # priorities (in default.nix) actually take effect. Loaded
          # unconditionally (a udev write to a non-existent scheduler silently
          # no-ops). VALIDATE post-deploy: confirm CPU headroom under scrub+stream
          # on this qemu guest; if CPU-bound, revert the udev rule to mq-deadline.
          kernelModules = [ "bfq" ];

          # Bound dirty memory by BYTES, not ratio. The VM now has 64 GiB
          # (EPYC host), so modules/base's dirty_ratio=20 / background=5 would
          # allow ~12.8 GiB / ~3.2 GiB of dirty pages -- far too much for slow
          # spindles; a writeback storm can monopolise a disk long enough to
          # time out a FUSE readdir. The cap is drain-rate-bound (spindle
          # speed), NOT RAM-bound, so it stays small despite the big page
          # cache. Cap by bytes and FORCE the ratio knobs to 0: ratio and bytes are mutually
          # exclusive and whichever sysctl is applied LAST wins, so a later
          # `sysctl --system` re-asserting ratio=20 would silently zero
          # dirty_bytes; pinning the ratios to 0 makes kernel state deterministic
          # regardless of apply order. These caps REDUCE memory pressure (RAM
          # safe). VALIDATE: vm.dirty_bytes==268435456 && vm.dirty_ratio==0 after
          # boot; watch large-copy / *arr-import write latency.
          kernel.sysctl = {
            "vm.dirty_background_bytes" = 67108864;   # 64 MiB
            "vm.dirty_bytes" = 268435456;             # 256 MiB
            "vm.dirty_ratio" = lib.mkForce 0;
            "vm.dirty_background_ratio" = lib.mkForce 0;
            # Hold dentries/inodes hard now the VM has 64 GiB: *arr scans and
            # cold readdir over 16 spindles are metadata-bound. base sets 25;
            # 10 makes the kernel strongly prefer evicting data pages over
            # metadata.
            "vm.vfs_cache_pressure" = lib.mkForce 10;
          };
        };

        # Put the rotational pool disks on BFQ (the 16+ HBA-passthrough SATA
        # disks are sd*; the virtio system disk vda is excluded by the sd[a-z]
        # match; rotational==1 excludes any SSD). See boot.kernelModules above.
        services.udev.extraRules = ''
          ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
        '';

        # This VM only has 8GB RAM and has 32GB LVM swap; zram causes OOM during boot
        zramSwap.enable = lib.mkForce false;

        # smartd starts before passthrough disks are available; retry until they appear
        systemd.services.smartd.serviceConfig = {
          Restart = "on-failure";
          RestartSec = "10s";
        };

        # Rescan SCSI bus after boot to detect disks the LSI controller missed,
        # then mount any newly-appeared disks and restart mergerfs
        systemd.services.scsi-rescan-and-mount = {
          description = "Rescan SCSI bus and mount late-appearing disks";
          after = [ "multi-user.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.util-linux pkgs.coreutils pkgs.gnugrep pkgs.attr pkgs.nfs-utils ];
          script = ''
            # Only do the DESTRUCTIVE SCSI rescan when a branch disk is actually
            # missing. Echoing "- - -" to every scsi_host forces the LSI HBA to
            # re-run discovery, which on this passthrough card emits a
            # `sata affiliation conflict` storm and can transiently drop a live
            # SATA drive behind the expander. When paired with the `systemctl
            # daemon-reload` this service USED to run, that reload re-evaluated
            # the fstab-generated media-storage.mount mid-device-flux and
            # UNMOUNTED the healthy pool — NFS then served empty stub dirs and
            # every client got ENOENT (silent total playback outage, 2026-07-21;
            # boot 0: pool mounted 17:46:18 -> daemon-reload 17:46:22 -> pool
            # Deactivated 17:46:23, never recovered). So: gate the rescan, and
            # NEVER daemon-reload here (the branch .mount units are static, built
            # from fileSystems — they already exist; starting them needs no
            # reload). The media-pool-watchdog below is the catch-all if the pool
            # ever drops anyway.
            expected=${toString (builtins.length mergerfsBranchMounts)}
            branches_mounted() {
              findmnt -rn -o TARGET 2>/dev/null | grep -c '^/media/disks/' || true
            }

            if [ "$(branches_mounted)" -lt "$expected" ]; then
              echo "branches $(branches_mounted)/$expected mounted -> SCSI rescan for late disks"
              for host in /sys/class/scsi_host/host*/scan; do
                echo "- - -" > "$host"
              done
              # Wait for udev to settle after rescan
              ${pkgs.systemd}/bin/udevadm settle --timeout=30
              # Start any disk mounts that are now satisfiable (NO daemon-reload).
              systemctl start --all 'media-disks-*.mount' 'media-parity-*.mount' 2>/dev/null || true
            else
              echo "all $expected branches mounted -> skip destructive SCSI rescan"
            fi

            # Ensure the pool is up (an earlier event may have dropped it). We
            # only ever START it here, never restart: if it is down nothing holds
            # it open so the mount succeeds; if it is up we no-op.
            if ! findmnt -t fuse.mergerfs /media/storage >/dev/null 2>&1; then
              systemctl start media-storage.mount || true
            fi

            # Re-add branches at runtime for any disk that appeared only after
            # the pool mounted. A `systemctl restart media-storage.mount` can
            # NEVER work here: nfsd/smbd hold the FUSE mount open, so the unmount
            # fails "target is busy" and the pool is left exactly as it was (this
            # is why the empty-pool state survived the 2026-07-20 power-loss
            # boot). The mergerfs runtime control file re-globs the branch spec
            # in place with no unmount. Idempotent when branches already present.
            # Guard: only poke a LIVE, mounted pool. Setting branches on a
            # zero-branch / dead FUSE endpoint can crash mergerfs ("Transport
            # endpoint is not connected"). The boot ordering above means the
            # pool is always healthy by the time this runs; the guard just stops
            # a degenerate state from being made worse.
            if [ -e /media/storage/.mergerfs ] \
              && mountpoint -q /media/storage \
              && stat /media/storage >/dev/null 2>&1; then
              setfattr -n user.mergerfs.branches -v '/media/disks/*' /media/storage/.mergerfs || true
            fi
            # Re-export so a now-present subtree (e.g. /media/storage/media) is
            # actually served rather than answered with ENOENT.
            exportfs -ra 2>/dev/null || true

            # Normalize the category top-dirs on any newly-mounted branch so
            # mergerfs (category.create=mfs, which routes new writes to the
            # emptiest disk) never lands imports on a branch whose backing
            # media/Movies|TV or downloads dir is still root-owned / non-setgid.
            systemctl start media-branch-normalize.service 2>/dev/null || true
          '';
        };

        # Normalize the media/downloads category top-dirs on EVERY mergerfs
        # branch: correct owner + setgid group + POSIX *default* ACLs. Because
        # setgid propagates the group and the default ACL propagates group-rwX to
        # all new children regardless of the writing service's umask, correctness
        # is INHERITED downward — so this only ever touches the ~5 top-dirs per
        # branch and is never a recursive file walk. Runs at boot and is
        # re-triggered by scsi-rescan-and-mount when a late disk appears.
        #
        # This is the load-bearing guard against the recurring *arr "Access to
        # the path ... is denied" import failures: a freshly-added pool disk's
        # top dirs are root-owned until seeded, and the merged tmpfiles.rules
        # below only reach a single branch via mergerfs, not each backing disk.
        systemd.services.media-branch-normalize = {
          description = "Normalize media/downloads top-dir ownership + default ACLs across all mergerfs branches";
          after = [ "media-storage.mount" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.coreutils pkgs.acl ];
          script = ''
            shopt -s nullglob
            for b in /media/disks/*/; do
              # install -d applies owner/group/mode to existing dirs too, so this
              # also repairs a branch whose top dir is currently root:root.
              install -d -o radarr      -g movies -m 2775 "$b/media/Movies"
              install -d -o sonarr      -g tv     -m 2775 "$b/media/TV"
              install -d -o qbittorrent -g media  -m 2775 \
                      "$b/downloads" "$b/downloads/complete" "$b/downloads/downloading"
              # Default ACLs: new files/dirs inherit group rwX regardless of the
              # writer's umask (covers jellyfin on k8s, which has no systemd UMask).
              setfacl -m g:movies:rwx -d -m g:movies:rwx "$b/media/Movies"
              setfacl -m g:tv:rwx     -d -m g:tv:rwx     "$b/media/TV"
              setfacl -m g:media:rwx  -d -m g:media:rwx \
                      "$b/downloads" "$b/downloads/complete" "$b/downloads/downloading"
            done
          '';
        };

        # Ordering barrier: the mergerfs pool must not mount before its branch
        # disks are mounted. The pool's device is the glob "/media/disks/*", and
        # systemd cannot derive an ordering from a glob string, so media-storage.
        # mount has no dependency on the individual disk mounts. On a cold boot
        # it therefore races them and wins, globbing zero branches -> the pool
        # comes up broken/empty and NFS answers ENOENT for every subtree
        # (root cause of the 2026-07-20 jellyfin/pharos mount failures).
        #
        # This oneshot gathers every branch-disk .mount unit and is inserted
        # between them and the pool mount (requiredBy + before media-storage.
        # mount). The disk deps are SOFT (wants + after, not requires) so a
        # single dead/absent disk still lets the barrier complete and the pool
        # mount with the remaining branches — preserving the fileSystems `nofail`
        # dead-disk tolerance. DefaultDependencies=false keeps the barrier inside
        # the local-fs ordering island (a normal service is ordered after
        # local-fs.target, which would form a cycle with media-storage.mount's
        # Before=local-fs.target).
        systemd.services.media-disks-ready = {
          description = "Barrier: mergerfs branch disks mounted before the pool";
          after = mergerfsBranchMounts;
          wants = mergerfsBranchMounts;
          before = [ "media-storage.mount" ];
          requiredBy = [ "media-storage.mount" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
          };
        };

        # Do not export/serve the pool until mergerfs has actually mounted with
        # its branches. Ordering only (after + wants, never requires) so a pool
        # problem degrades to "server waiting", not NFS/SMB fully down. Combined
        # with the barrier above (which media-storage.mount now requires), this
        # guarantees exportfs runs against a populated pool, never an empty one.
        systemd.services.nfs-server = {
          after = [ "media-storage.mount" ];
          wants = [ "media-storage.mount" ];
        };
        systemd.services.samba-smbd = {
          after = [ "media-storage.mount" ];
          wants = [ "media-storage.mount" ];
        };

        environment = {
          pathsToLink = [ "/share/zsh" ];

          systemPackages = with pkgs; [
            parted
            xfsprogs
          ];

          variables = {
            PATH = [
              "\${HOME}/.local/bin"
              "\${HOME}/.config/rofi/scripts"
            ];
          };
        };

        networking = {
          hostName = "home-storage-server-1";
          networkmanager.enable = true;

          firewall = {
            enable = true;
            allowPing = true;

            allowedTCPPorts = [
              22
              2049  # NFS
              111   # RPC
            ];
            allowedUDPPorts = [
              2049  # NFS
              111   # RPC
            ];
          };

          # Static config for the second (jumbo) NIC on br-storage, bound by its
          # fixed MAC. Isolated point-to-point with download-server-1 (10.10.10.1);
          # no gateway/DNS. MTU 9000 must match every hop (bridge + taps + peer).
          networkmanager.ensureProfiles.profiles = {
            storage-jumbo = {
              connection = {
                id = "storage-jumbo";
                type = "ethernet";
                autoconnect = true;
              };
              ethernet = {
                mac-address = "52:54:00:69:9C:40";
                mtu = 9000;
              };
              ipv4 = {
                method = "manual";
                address1 = "10.10.10.2/24";
              };
              ipv6.method = "disabled";
            };
          };
        };

        # Turn on virtio-net multiqueue (the device offers 4 queues but Linux
        # uses 1 until told). Spreads NIC softirq across the 4 vCPUs under the
        # parallel NFS streams. Matches by driver so it covers both NICs.
        systemd.services.virtio-nic-multiqueue = {
          description = "Enable virtio-net multiqueue on all virtio NICs";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = [ pkgs.ethtool pkgs.coreutils pkgs.gawk ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            for dev in /sys/class/net/*; do
              name=$(basename "$dev")
              [ -e "$dev/device/driver" ] || continue
              case "$(readlink "$dev/device/driver")" in *virtio*) ;; *) continue ;; esac
              max=$(ethtool -l "$name" 2>/dev/null | awk '/^Combined:/{print $2; exit}')
              [ -n "$max" ] && [ "$max" -gt 1 ] && ethtool -L "$name" combined "$max" || true
            done
          '';
        };

        # Set proper ownership and permissions on media directories
        systemd.tmpfiles.rules = [
          # Impermanence: ensure /var/run is a symlink to ../run.
          # The default 'L' rule doesn't replace an existing directory.
          "L+ /var/run - - - - ../run"

          # Downloads directory: owner=qbittorrent, group=media, setgid bit
          "d /media/storage/downloads 2775 qbittorrent media -"
          "d /media/storage/downloads/downloading 2775 qbittorrent media -"
          "d /media/storage/downloads/complete 2775 qbittorrent media -"

          # Movies directory: owner=radarr, group=movies
          "d /media/storage/media/Movies 2775 radarr movies -"

          # TV directory: owner=sonarr, group=tv
          "d /media/storage/media/TV 2775 sonarr tv -"
        ];

        services = {
          logrotate.checkConfig = false;

          smartd = {
            enable = true;
            autodetect = true;
            notifications = {
              mail.enable = true;
              wall.enable = true;
            };
            defaults.monitored = "-a -o on -s (S/../.././02|L/../../6/03)";
          };

          # NFS Server - runs alongside Samba for performance comparison
          nfs.server = {
            enable = true;
            # Lock to NFSv4 only for better performance and security
            lockdPort = 4001;
            mountdPort = 4002;
            statdPort = 4000;
            # 32 nfsd threads (default 8). Under a scrub/recheck stall all 8
            # default threads park on slow mergerfs getattr/readdir and queue
            # every other client, which surfaces as client-visible stalls /
            # incomplete listings. 32 threads cost only a few KiB kernel stack
            # each (negligible on this RAM-tight box); kept <=32 so we don't
            # over-drive the 16 spindles. Check /proc/net/rpc/nfsd 'th' line.
            nproc = 32;

            exports = ''
              # Downloads share - optimized for qBittorrent on download-server
              # no_root_squash: Allow root access from client
              # no_subtree_check: Better performance, safe for dedicated exports
              # sync: Ensure data integrity on server (client uses async for speed)
              #
              # fsid=<random UUID> per export (NOT 1/2/3): the pool is a
              # fuse.mergerfs union, and FUSE filesystems share st_dev across
              # branches, which destabilises NFS filehandles -> ESTALE / "files
              # gone" on clients, independent of the readdir-truncation bug.
              # mergerfs remote_filesystems.md: "set each mergerfs export fsid to
              # some random value ... use uuidgen". Do NOT add crossmnt/nohide
              # (these are sibling subtrees of one mergerfs mount with no child
              # mounts; crossmnt synthesises submount filehandles on a FUSE export
              # lacking distinct st_dev -> more ESTALE). Do NOT switch to async.
              /media/storage/downloads    192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=9ec7c92a-1c8c-42c1-8b41-77a4a0138268)

              # Movies share - for Radarr
              /media/storage/media/Movies 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=32607c05-4f67-428c-95b1-26de08ae4078)

              # TV share - for Sonarr
              /media/storage/media/TV     192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=00a0212d-447f-487d-afbc-3faaafab5b73)

              # Pool-ROOT export for download-server-1 ONLY, so it mounts the
              # whole union once and Sonarr/Radarr can HARDLINK imports
              # (downloads + media library under one st_dev) instead of copying
              # every file back over NFS. Own fresh random fsid (mergerfs/FUSE
              # shares st_dev -> each export needs a distinct fsid). NO
              # crossmnt/nohide (ESTALE on FUSE). Own fresh random fsid. Clients:
              # 10.10.10.1 = download-server-1's jumbo IP, 10.10.10.3 =
              # home-k8s-master-1's jumbo IP (Jellyfin mounts the media/ subdir
              # over this off the LAN br0), plus download's LAN FQDN as a fallback.
              /media/storage  10.10.10.1(rw,sync,no_subtree_check,no_root_squash,fsid=e3fdacb1-c2cf-472d-b686-b53f12e8639f) 10.10.10.3(rw,sync,no_subtree_check,no_root_squash,fsid=e3fdacb1-c2cf-472d-b686-b53f12e8639f) download-server-1.lan(rw,sync,no_subtree_check,no_root_squash,fsid=e3fdacb1-c2cf-472d-b686-b53f12e8639f)
            '';
          };

          samba = {
            enable = true;
            openFirewall = true;

            settings = {
              global = {
                "aio read size" = "16384";
                "aio write size" = "16384";
                # Cap aio worker threads (default 100). A single smbd can spawn
                # up to 100 aio pthreads -> per-thread stacks (RAM) + a seek-storm
                # that starves the synchronous readdir/getattr path Jellyfin's
                # scan uses. 8 suits an effectively single-streamer workload.
                # (VALIDATE: scan+playback overlap.)
                "aio max threads" = "8";
                # Pin SMB 3.1.1 min: large credits + durable handles so a session
                # survives a long server-side stall without teardown (the
                # prune-on-stall window). Verified the only client (Jellyfin
                # cifs) already negotiates vers=3.1.1, so this breaks nothing.
                "server min protocol" = "SMB3_11";
                "getwd cache" = "yes";
                "oplocks" = "yes";
                # Disable KERNEL oplocks on the FUSE (mergerfs) backend: kernel
                # oplocks on FUSE can stall under concurrent access. Userspace
                # oplocks above stay on. (case-sensitive=true would speed scans
                # further but breaks case-insensitive macOS/Windows access, so
                # left at the safe default.)
                "kernel oplocks" = "no";
                "read raw" = "yes";
                # No hard-coded SO_RCVBUF/SO_SNDBUF: pinning them disables Linux
                # TCP window auto-tuning, hurting LAN throughput and post-stall
                # scan recovery. (VALIDATE: large-copy benchmark.)
                "socket options" = "TCP_NODELAY IPTOS_LOWDELAY";
                "use sendfile" = "yes";
                "write raw" = "yes";

                # Drop per-entry xattr probing. Both default "yes" in Samba 4.x:
                # store dos attributes -> read/write user.DOSATTRIB xattr per
                # file; ea support -> extra EA probing. On mergerfs every
                # getxattr() fans across all 16 branches, a real per-entry cost
                # when enumerating a several-hundred-entry dir during a stall
                # (the listing-truncation/scan-timeout window). Jellyfin/*arr
                # don't need DOS-attr bits; with this off Samba maps them onto
                # the unix perm bits already in the readdir lstat (no syscalls).
                "store dos attributes" = "no";
                "ea support" = "no";
                # Regression guards (defaults, pinned intentionally):
                # - vfs objects empty: never add acl_xattr/streams_xattr/fruit/
                #   recycle/full_audit -- each does per-file getxattr() fanned
                #   across all branches, re-introducing the per-entry stall.
                # - strict sync stays on: a future "strict sync=no" speed hack
                #   would widen the torn / zero-length-file window on a parity
                #   (snapraid) pool.
                "vfs objects" = "";
                "strict sync" = "yes";
                "smbd async dosmode" = "no";
              };

              "storage" = {
                path = "/media/storage";
                browseable = "yes";
                "read only" = "no";
                "guest ok" = "no";
                "valid users" = "ali";
              };

              "k8s-storage" = {
                path = "/media/storage/k8s-storage";
                browseable = "yes";
                "read only" = "no";
                "guest ok" = "no";
                "valid users" = "privoxy monitoring";
              };

              "media" = {
                path = "/media/storage/media";
                browseable = "yes";
                "read only" = "no";
                "guest ok" = "no";
                "valid users" = "ali jellyfin";
              };

              "movies" = {
                path = "/media/storage/media/Movies";
                browseable = "yes";
                "read only" = "no";
                "guest ok" = "no";
                "valid users" = "ali radarr";
              };

              "tv" = {
                path = "/media/storage/media/TV";
                browseable = "yes";
                "read only" = "no";
                "guest ok" = "no";
                "valid users" = "ali sonarr";
              };

              "downloads" = {
                path = "/media/storage/downloads";
                browseable = "yes";
                "read only" = "no";
                "guest ok" = "no";
                "valid users" = "download-server";
              };
            };
          };

          samba-wsdd = {
            enable = true;
            openFirewall = true;
          };

          snapraid = let
            dataDisks = lib.attrsets.filterAttrs (mountPoint: diskOptions:
              lib.strings.hasPrefix "/media/disks" mountPoint
            ) config.fileSystems;

            parityDisks = lib.attrsets.filterAttrs (mountPoint: diskOptions:
              lib.strings.hasPrefix "/media/parity" mountPoint
            ) config.fileSystems;

            contentFilesOpt = lib.lists.map (item: "${item}/snapraid.content") ((builtins.attrNames dataDisks) ++ (builtins.attrNames parityDisks));
            parityFilesOpt = lib.lists.map (item: "${item}/snapraid.parity") (builtins.attrNames parityDisks);

            dataDisksOpt = builtins.map (mountPoint:
              let
                diskName = lib.strings.replaceStrings ["/media/disks/"] [""] mountPoint;
              in
              {
                name = diskName;
                value = mountPoint;
              }
            ) (builtins.attrNames dataDisks);
          in {
            # Disable SnapRAID in VM since we don't have the complex disk setup
            enable = !config.system.isVM;

            contentFiles = contentFilesOpt;
            dataDisks = (builtins.listToAttrs dataDisksOpt);
            parityFiles = parityFilesOpt;
          };
        };

        # Defer the daily SnapRAID sync AND scrub while the array is busy (heavy
        # NFS downloads / Jellyfin scans saturate the spinning disks, and parity
        # work on top of that thrashes everything -> client readdir stalls that
        # read as "files gone"). ExecCondition runs before the unit: exit 0 =
        # proceed, non-zero = skip this run (systemd marks it "condition failed",
        # not an error); the daily/weekly timer simply retries on the next calm
        # cycle, so it waits out a catch-up automatically. Gate: sustained IO
        # pressure ("some" avg300, a 5-min average) below 40%; idle ~0-10, heavy
        # serving ~85. A read failure defaults to "calm" so it's never blocked
        # forever. The SCRUB was previously ungated and ran at the exact bug
        # window -- gating it is the highest-leverage fix.
        #
        # IOSchedulingClass=idle so an incoming nfsd/smbd read preempts the
        # parity job. NOTE: only the BFQ I/O scheduler honours the idle class;
        # under mq-deadline/none this is inert (harmless) -- BFQ on the
        # rotational pool disks is a separate [VALIDATE-FIRST] change.
        systemd.services.snapraid-sync.serviceConfig = let
          deferCheck = pkgs.writeShellScript "snapraid-defer-check" ''
            A=$(${pkgs.gawk}/bin/awk '/^some/{for(i=1;i<=NF;i++) if($i ~ /^avg300=/){sub(/avg300=/,"",$i); print $i}}' /proc/pressure/io)
            ${pkgs.gawk}/bin/awk -v a="''${A:-0}" 'BEGIN{ exit !((a+0) < 40) }'
          '';
        in {
          ExecCondition = "${deferCheck}";
          IOSchedulingClass = "idle";
        };
        systemd.services.snapraid-scrub.serviceConfig = let
          # Identical script name+content -> same /nix/store path as the sync
          # gate above (no duplication cost).
          deferCheck = pkgs.writeShellScript "snapraid-defer-check" ''
            A=$(${pkgs.gawk}/bin/awk '/^some/{for(i=1;i<=NF;i++) if($i ~ /^avg300=/){sub(/avg300=/,"",$i); print $i}}' /proc/pressure/io)
            ${pkgs.gawk}/bin/awk -v a="''${A:-0}" 'BEGIN{ exit !((a+0) < 40) }'
          '';
        in {
          ExecCondition = "${deferCheck}";
          IOSchedulingClass = "idle";
        };

        # Prioritise smbd's I/O + CPU over the idle-class parity scrubber so a
        # Jellyfin SMB readdir/read is dispatched ahead of background work (the
        # consumer-side symmetry to the idle class on snapraid above; takes full
        # effect under BFQ). Samba serves each client in a userspace smbd
        # process, so unlike knfsd (kernel kthreads, not tunable here) this
        # works. Unit name confirmed as samba-smbd.service.
        systemd.services."samba-smbd".serviceConfig = {
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 0;
          Nice = -5;
        };

        sops = {
          defaultSopsFile = self + "/secrets/main.enc.yaml";
          defaultSopsFormat = "yaml";
          age.sshKeyPaths = [ "/persistence/etc/ssh/keys/ssh_host_ed25519_key" ];

          secrets = builtins.listToAttrs (map (user: {
            name = "samba/${user}";
            value = {
              format = "yaml";
              group = config.users.users.root.group;
              mode = "0400";
              owner = config.users.users.root.name;
              sopsFile = ./secrets/samba-passwords.enc.yaml;
            };
          }) sambaUsers);
        };

        systemd.services.samba-setup-passwords = {
          description = "Set Samba user passwords from sops secrets";
          after = [ "samba-smbd.service" ];
          requiredBy = [ "samba-smbd.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = lib.concatMapStringsSep "\n" (user: ''
            password=$(cat "${config.sops.secrets."samba/${user}".path}")
            printf '%s\n%s\n' "$password" "$password" | ${pkgs.samba}/bin/smbpasswd -s -a "${user}"
          '') sambaUsers;
        };

        system = {
          stateVersion = "24.05";
        };

        security = {
          sudo = {
            wheelNeedsPassword = lib.mkForce false;
          };
        };

        users = {
          groups = {
            # Fixed GIDs to match download-server-1
            bazarr = { gid = 5007; };
            download-server = { gid = 5004; };
            games = { gid = 5014; };
            jellyfin = { gid = 5005; };
            media = { gid = 5000; };  # Shared group for all media services
            movies = { gid = 5011; };
            music = { gid = 5012; };
            privoxy = { gid = 5006; };
            qbittorrent = { gid = 5001; };
            radarr = { gid = 5002; };
            sonarr = { gid = 5003; };
            tv = { gid = 5013; };
            deluge = { gid = 5010; };
            monitoring = { gid = 5015; };
          };

          users = {
            ali = {
              description = "Alison Jenkins";
              extraGroups = [
                "docker"
                "games"
                "movies"
                "music"
                "networkmanager"
                "tv"
                "wheel"
              ];
              # hashedPasswordFile = config.sops.secrets.ali.path;
              hashedPasswordFile = "/persistence/passwords/ali";
              # initialPassword = "initPw!";
              isNormalUser = true;
              openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];
            };
            bazarr = {
              description = "Bazarr user";
              group = "bazarr";
              uid = 5007;
              extraGroups = ["media" "movies" "tv"];  # Add to shared media group
              home = "/var/lib/bazarr";
              createHome = false;
              isSystemUser = true;
            };
            download-server = {
              description = "Download Server user";
              group = "download-server";
              uid = 5004;
              hashedPasswordFile = "/persistence/passwords/download-server";
              isNormalUser = true;
            };
            # Add qbittorrent user to match download server
            qbittorrent = {
              description = "qBittorrent user";
              group = "qbittorrent";
              uid = 5001;
              extraGroups = ["media"];  # Add to shared media group
              home = "/var/lib/qBittorrent";
              createHome = false;
              isSystemUser = true;
            };
            radarr = {
              description = "Radarr user";
              group = "radarr";
              uid = 5002;
              extraGroups = ["media" "movies"];  # Add to shared media group
              hashedPasswordFile = "/persistence/passwords/radarr";
              isNormalUser = true;
            };
            sonarr = {
              description = "Sonarr user";
              group = "sonarr";
              uid = 5003;
              extraGroups = ["media" "tv"];  # Add to shared media group
              hashedPasswordFile = "/persistence/passwords/sonarr";
              isNormalUser = true;
            };
            jellyfin = {
              description = "Jellyfin user";
              group = "jellyfin";
              uid = 5005;
              extraGroups = ["media" "movies" "tv" "music"];  # Add to shared media group
              hashedPasswordFile = "/persistence/passwords/jellyfin";
              isNormalUser = true;
            };
            privoxy = {
              description = "Privoxy user";
              group = "privoxy";
              uid = 5006;
              hashedPasswordFile = "/persistence/passwords/privoxy";
              isNormalUser = true;
            };
            monitoring = {
              description = "Monitoring user";
              group = "monitoring";
              uid = 5015;
              hashedPasswordFile = "/persistence/passwords/monitoring";
              isNormalUser = true;
            };
            deluge = {
              description = "Deluge user";
              group = "deluge";
              uid = 5010;
              extraGroups = ["media"];
              home = "/var/lib/deluge";
              createHome = false;
              isSystemUser = true;
            };
            root = {
              hashedPasswordFile = "/persistence/passwords/root";
            };
          };
        };
      })
    ];
  };
}
