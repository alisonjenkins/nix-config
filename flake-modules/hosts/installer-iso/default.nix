{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in
{
  flake.nixosConfigurations.installer-iso = lib.nixosSystem {
    specialArgs = {
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }
      "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-base.nix"
      (
        { pkgs, inputs, ... }:
        let
          # disko CLI from the same source revision that produces the
          # nixosModule used by host configs (`inputs.disko`). Using a
          # `nix run github:nix-community/disko` would pull master and
          # risk CLI ↔ module version drift, which surfaces as a
          # spurious "config not found" at install time. We use plain
          # `disko` (format + mount) followed by `nixos-install --root
          # /mnt --flake ...` rather than the all-in-one
          # `disko-install` wrapper, because nixos-install passes
          # `--store /mnt` to nix build so substitutions land DIRECTLY
          # on the target's btrfs nix store. disko-install would
          # build into the live tmpfs first then copy, doubling RAM
          # use and tripping systemd-oomd's PSI-based pre-emptive
          # kill.
          diskoPkg = inputs.disko.packages.${system}.disko;
          installNixos = pkgs.writeShellApplication {
            name = "install-nixos";
            runtimeInputs = [
              diskoPkg
            ] ++ (with pkgs; [
              coreutils
              gawk
              git
              gnugrep
              gnused
              jq
              kdePackages.kdialog
              kdePackages.konsole
              networkmanager
              util-linux
              nix
            ]);
            text = ''
              set -euo pipefail

              # Raise the soft file-descriptor limit to the hard
              # limit. nix opens many .drv / NAR / cache files in
              # parallel during substitution and hits the default
              # 1024 cap as "Too many open files" on big closures
              # (ali-steam-deck has multi-thousand store paths).
              ulimit -Sn "$(ulimit -Hn)" || true

              # Tee everything to a log file so the user can read it
              # later if konsole closes or output scrolls off.
              LOG=/tmp/install-nixos.log
              exec > >(tee -a "$LOG") 2>&1

              # Show line numbers in `set -x` traces if we ever flip
              # them on. PS4 is shell-only; harmless when -x is off.
              export PS4='+ [$LINENO] '

              # ERR trap: any unhandled failure under `set -e` prints
              # the failing line + command and pops a kdialog so the
              # user knows WHY install-nixos exited. Konsole's --hold
              # keeps the window open after this trap fires.
              trap 'rc=$?; echo; echo "==> install-nixos ABORTED (exit $rc) at line $LINENO: $BASH_COMMAND" >&2; echo "==> df -h post-mortem:" >&2; df -h >&2 || true; kdialog --error "install-nixos aborted (exit $rc).\n\nLine $LINENO: $BASH_COMMAND\n\nFull log: $LOG" 2>/dev/null || true; exit $rc' ERR

              # Print a visible banner before each phase so the user
              # always knows what the script is doing.
              step() { echo; echo "==> $*"; echo; }

              # Run "$@" in a loop; on non-zero exit, ask the user
              # what to do via kdialog instead of letting the ERR
              # trap blow the script away. Returns:
              #   0 — command succeeded (eventually)
              #   1 — user chose abort
              #   2 — user chose pull-redisko (caller restarts from
              #       disko)
              # `set +e` round the actual command suppresses the
              # script-wide ERR trap — we WANT to handle failure
              # locally here.
              retry_loop() {
                local label="$1"
                shift
                while true; do
                  set +e
                  "$@"
                  local rc=$?
                  set -e
                  if [ "$rc" -eq 0 ]; then
                    return 0
                  fi
                  echo
                  echo "==> $label failed (exit $rc) — prompting user for next action"
                  local choice
                  choice=$(kdialog --title "$label failed (exit $rc)" \
                    --menu "What now?" \
                    retry        "Retry as-is (best for transient network/DNS errors)" \
                    pull         "git pull origin then retry (config fix already pushed)" \
                    pull-redisko "git pull then re-format AND retry (DESTROYS partial install)" \
                    abort        "Abort install-nixos") || return 1
                  case "$choice" in
                    retry) ;;
                    pull)
                      local git_out
                      if ! git_out=$(git -C "$REPO" pull --ff-only 2>&1); then
                        kdialog --error "git pull failed:\n\n$git_out"
                      else
                        kdialog --passivepopup "$git_out" 5
                      fi
                      ;;
                    pull-redisko)
                      local git_out
                      if ! git_out=$(git -C "$REPO" pull --ff-only 2>&1); then
                        kdialog --error "git pull failed:\n\n$git_out"
                        continue
                      fi
                      kdialog --passivepopup "$git_out" 5
                      return 2
                      ;;
                    abort) return 1 ;;
                  esac
                done
              }

              echo "==================================================="
              echo " install-nixos starting at $(date -Iseconds)"
              echo " log file: $LOG"
              echo "==================================================="

              REPO=/home/nixos/nix-config
              REPO_URL=https://github.com/alisonjenkins/nix-config.git

              step "Locating nix-config repo at $REPO"
              # Wait for the clone-nix-config service to finish, then fall
              # back to cloning inline so the user doesn't have to drop to
              # a terminal if the boot-time clone failed (e.g. no network
              # at boot).
              while [ ! -d "$REPO/.git" ]; do
                echo "  no repo yet — attempting fresh clone from $REPO_URL"
                if git clone --depth 1 "$REPO_URL" "$REPO"; then
                  continue
                fi
                kdialog --warningyesno \
                  "Failed to clone nix-config into $REPO.\n\nSee terminal / $LOG for details. Check network then click Yes to retry, or No to abort." \
                  || exit 0
                rm -rf "$REPO"
              done
              cd "$REPO"
              echo "  repo present at $REPO ($(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown) on $(git -C "$REPO" branch --show-current 2>/dev/null || echo unknown))"

              step "Asking whether to update nix-config from origin"
              # Offer to pull latest changes from origin. Default to skip
              # so a cached repo "just works" but the user can refresh
              # without rebooting the installer.
              UPDATE_CHOICE=$(kdialog --title "Update nix-config" \
                --menu "Update $REPO from origin before installing?" \
                skip "Use what's already on disk (default)" \
                pull "Fast-forward pull (preserves local edits)" \
                reset "Hard reset to origin/HEAD (DISCARDS local edits)" \
                ) || exit 0
              echo "  user chose: $UPDATE_CHOICE"

              case "$UPDATE_CHOICE" in
                pull)
                  if ! git_out=$(git -C "$REPO" pull --ff-only 2>&1); then
                    kdialog --error "git pull failed:\n\n$git_out"
                    exit 1
                  fi
                  kdialog --passivepopup "$git_out" 5
                  ;;
                reset)
                  kdialog --warningcontinuecancel \
                    "This will discard ALL local edits in $REPO. Continue?" \
                    || exit 0
                  if ! git_out=$( {
                    git -C "$REPO" fetch origin
                    git -C "$REPO" reset --hard origin/HEAD
                    git -C "$REPO" clean -fdx
                  } 2>&1); then
                    kdialog --error "git update failed:\n\n$git_out"
                    exit 1
                  fi
                  kdialog --passivepopup "Reset to origin/HEAD" 5
                  ;;
                skip|*) ;;
              esac

              step "Checking for network connectivity"
              # Internet precheck — nix eval / git pull need network. Loop
              # with a user-friendly prompt rather than letting nix fail
              # with a network error. The user is expected to run the
              # `Connect WiFi` desktop launcher (or use Plasma's NM tray
              # applet) before reaching this point.
              while ! nm-online -t 2 -q 2>/dev/null; do
                echo "  nm-online: no connectivity — prompting user"
                kdialog --warningyesno \
                  "No network connection detected.\n\nUse the Connect WiFi launcher (or NM tray icon) then click Yes to retry. No aborts." \
                  || exit 0
              done
              echo "  network: OK"

              step "Listing host configurations from flake (this can take several minutes on first run while flake inputs download — watch the terminal for progress)"
              # Host picker. Re-evaluate on each loop iteration so the
              # user can edit the flake locally and rescan without
              # restarting the launcher.
              #
              # NOTE: stderr is intentionally NOT captured — it streams
              # live to the terminal so the user can see nix's
              # download/build progress instead of staring at a blank
              # window. Only stdout (the JSON we need) is captured.
              while true; do
                err_log=$(mktemp)
                if HOSTS_JSON=$(nix eval --json .#nixosConfigurations \
                    --apply 'cfgs: builtins.attrNames cfgs' \
                    --print-build-logs \
                    2> >(tee "$err_log" >&2)); then
                  rm -f "$err_log"
                else
                  rc=$?
                  err_tail=$(tail -c 2000 "$err_log")
                  rm -f "$err_log"
                  echo "  nix eval failed (exit $rc)"
                  kdialog --warningyesno \
                    "nix eval failed (exit $rc):\n\n$err_tail\n\nFix the flake then click Yes to retry, or No to abort." \
                    || exit 0
                  continue
                fi
                HOSTS=$(echo "$HOSTS_JSON" | jq -r '.[]' \
                  | grep -vE '^installer-iso$' | sort || true)
                if [ -z "$HOSTS" ]; then
                  echo "  no installable hosts after filtering installer-iso"
                  kdialog --warningyesno \
                    "No installable nixosConfigurations found.\n\nClick Yes to retry, or No to abort." \
                    || exit 0
                  continue
                fi
                echo "  found hosts: $(echo "$HOSTS" | tr '\n' ' ')"

                menu_args=()
                while IFS= read -r h; do
                  menu_args+=("$h" "$h")
                done <<< "$HOSTS"

                HOST=$(kdialog --title "Install NixOS" \
                  --menu "Select host configuration to install:" \
                  "''${menu_args[@]}") || exit 0
                [ -n "$HOST" ] && break
              done
              echo "  selected host: $HOST"

              step "Picking target disk for $HOST"
              # Disk picker with rescan loop — handles late-plugged USB.
              while true; do
                disk_args=()
                while read -r name size model; do
                  [ -n "$name" ] || continue
                  disk_args+=("/dev/$name" "$size  $model")
                done < <(lsblk -dn -o NAME,SIZE,MODEL -e 7,11)

                if [ ''${#disk_args[@]} -eq 0 ]; then
                  kdialog --warningyesno \
                    "No installable disks detected.\n\nPlug a disk in then click Yes to rescan, or No to abort." \
                    || exit 0
                  continue
                fi

                DISK=$(kdialog --title "Target disk" \
                  --menu "Select target disk for $HOST.\nALL DATA WILL BE ERASED." \
                  "''${disk_args[@]}") || exit 0
                [ -n "$DISK" ] && break
              done
              echo "  selected disk: $DISK"

              step "Install mode: fresh wipe vs resume"
              INSTALL_MODE=$(kdialog --title "Install mode for $HOST" \
                --menu "Pick fresh install or resume an interrupted one." \
                fresh  "Wipe target + install (DESTROYS existing data on $DISK)" \
                resume "Mount existing layout + continue install (preserves data)" \
                ) || exit 0
              echo "  selected mode: $INSTALL_MODE"

              if [ "$INSTALL_MODE" = "fresh" ]; then
                step "Final confirmation before erasing $DISK"
                kdialog --warningcontinuecancel \
                  "About to ERASE $DISK and install $HOST.\n\nThis cannot be undone. Continue?" \
                  || exit 0
              fi

              step "Collecting LUKS password"
              # LUKS password loop: re-prompt on empty input.
              # Fresh mode: confirm a NEW password (used for luksFormat).
              # Resume mode: just type the EXISTING password (used to
              # open the already-formatted LUKS via disko --mode mount).
              # Cancel button still aborts.
              if [ "$INSTALL_MODE" = "fresh" ]; then
                pwd_prompt="LUKS password for disk encryption (new):"
              else
                pwd_prompt="EXISTING LUKS password to unlock $DISK:"
              fi
              while true; do
                PWD1=$(kdialog --password "$pwd_prompt") || exit 0
                if [ -z "$PWD1" ]; then
                  kdialog --sorry "Password cannot be empty. Try again."
                  continue
                fi
                if [ "$INSTALL_MODE" = "fresh" ]; then
                  PWD2=$(kdialog --password "Confirm LUKS password:") || exit 0
                  if [ "$PWD1" != "$PWD2" ]; then
                    kdialog --sorry "Passwords don't match. Try again."
                    continue
                  fi
                fi
                break
              done

              # Write password to keyfile with NO trailing newline so that
              # cryptsetup matches when the user types it at boot.
              printf '%s' "$PWD1" | sudo tee /tmp/secret.key > /dev/null
              sudo chmod 600 /tmp/secret.key
              unset PWD1 PWD2

              # We're already running inside konsole (see the desktop
              # launcher's `Exec=konsole --hold -e install-nixos`), so
              # disko + nixos-install can run inline and stream output
              # straight to the user's terminal. Wipe the LUKS keyfile
              # on exit even on failure.
              trap 'sudo rm -f /tmp/secret.key' EXIT

              # Sanity: the user-picked $DISK is purely informational
              # — plain `disko` has no --disk flag (only --argstr,
              # which needs function-style configs). The actual
              # device used is whatever the host's disko-config
              # `lib.mkDefault "/dev/..."` says. Warn loudly if those
              # don't match so the user can abort before we wipe the
              # wrong disk.
              expected=$(nix eval --no-warn-dirty --raw \
                ".#nixosConfigurations.$HOST.config.disko.devices.disk.disk1.device" \
                2>/dev/null || echo "")
              if [ -n "$expected" ] && [ "$expected" != "$DISK" ]; then
                if [ "$INSTALL_MODE" = "fresh" ]; then
                  kdialog --warningyesno \
                    "WARNING: you picked $DISK but the disko config for $HOST hardcodes $expected.\n\nDisko will use $expected — your $DISK selection is IGNORED.\n\nProceed with $expected?\n\nTo install onto $DISK instead, abort and edit the host's disko-config.nix to change the \`device\` field." \
                    || exit 0
                else
                  kdialog --passivepopup "Resume mode: ignoring picker, using $expected (per disko config)" 5 || true
                fi
                DISK="$expected"
              fi

              step "Disk usage before format + install"
              df -h

              # Outer loop: handles "pull-redisko" by restarting
              # from disko. Inner retry_loop handles transient
              # failures (DNS, substituter timeouts, etc.) without
              # losing partial install progress on /mnt.
              while true; do
                case "$INSTALL_MODE" in
                  fresh)
                    step "Running disko (format + mount $DISK)"
                    retry_loop "disko" sudo disko \
                      --mode destroy,format,mount \
                      --yes-wipe-all-disks \
                      --flake ".#$HOST"
                    rc=$?
                    [ "$rc" = 1 ] && exit 0  # user aborted

                    step "Enrolling TPM2 as a LUKS keyslot (PCR 7) for $HOST"
                    # If the target has a TPM, add a TPM-bound keyslot
                    # to the LUKS partition so subsequent boots can
                    # auto-unlock without a keyboard. Bound to PCR 7
                    # (UEFI Secure Boot state) so the seal is stable
                    # across kernel/grub updates. The original password
                    # keyslot stays as a fallback. Non-fatal — install
                    # proceeds even if enrollment is impossible (no TPM,
                    # no LUKS partition, etc).
                    luks_part=$(sudo lsblk -lno NAME,FSTYPE "$DISK" \
                      | awk '$2 == "crypto_LUKS" { print "/dev/"$1; exit }')
                    if [ -z "$luks_part" ]; then
                      echo "  no crypto_LUKS partition found on $DISK — skipping TPM enrollment"
                      kdialog --sorry "Could not locate the LUKS partition on $DISK to enroll TPM2.\n\nContinuing without TPM unlock — you'll need a USB keyboard at boot." 2>/dev/null || true
                    elif [ ! -e /dev/tpmrm0 ] && [ ! -e /dev/tpm0 ]; then
                      echo "  no TPM device on this hardware — skipping TPM enrollment"
                      kdialog --sorry "No TPM device detected (/dev/tpm{rm0,0} both missing).\n\nContinuing without TPM unlock — you'll need a USB keyboard at boot." 2>/dev/null || true
                    else
                      echo "  enrolling TPM on $luks_part (PCR 7)"
                      if ! sudo systemd-cryptenroll \
                            --unlock-key-file=/tmp/secret.key \
                            --tpm2-device=auto \
                            --tpm2-pcrs=7 \
                            "$luks_part"; then
                        echo "  TPM enrollment FAILED — continuing without TPM unlock"
                        kdialog --error "TPM2 enrollment failed. Continuing install — you'll need a USB keyboard at boot. The original password keyslot still works." 2>/dev/null || true
                      fi
                    fi
                    ;;

                  resume)
                    step "Mounting existing LUKS + btrfs layout for $HOST (no format)"
                    # Just mount per the disko config, no format. LUKS
                    # opens via /tmp/secret.key (the existing password
                    # the user typed above). TPM keyslot stays as-is.
                    retry_loop "disko mount" sudo disko \
                      --mode mount \
                      --flake ".#$HOST"
                    rc=$?
                    [ "$rc" = 1 ] && exit 0  # user aborted
                    ;;
                esac

                step "Running nixos-install (substitutes directly to /mnt)"
                # `--root /mnt` makes nixos-install pass `--store
                # /mnt` to nix build, so the closure substitutes
                # straight to the target's btrfs nix store. The
                # live tmpfs nix store stays nearly empty — no
                # memory pressure, no systemd-oomd kill.
                retry_loop "nixos-install" sudo nixos-install \
                  --flake ".#$HOST" \
                  --no-root-passwd \
                  --root /mnt
                rc=$?
                case "$rc" in
                  0) break ;;     # success
                  1) exit 0 ;;    # user aborted
                  2) continue ;;  # pull-redisko: re-run disko + install
                esac
              done

              echo
              echo "=========================================="
              echo " Install complete. Press Enter to reboot."
              echo "=========================================="
              read -r _
              sudo reboot
            '';
          };

          # WiFi launcher that bypasses plasma-nm + kwallet entirely.
          # Talks straight to NetworkManager via `nmcli` so there is no
          # secret-agent in the loop — `psk-flags=0` from
          # `connection-defaults` means NM stores the PSK system-wide.
          connectWifi = pkgs.writeShellApplication {
            name = "connect-wifi";
            runtimeInputs = with pkgs; [
              coreutils
              gawk
              gnused
              kdePackages.kdialog
              networkmanager
            ];
            text = ''
              set -euo pipefail

              # Make sure the radio is on. `nmcli radio wifi on` is a
              # no-op if it's already on.
              nmcli radio wifi on >/dev/null 2>&1 || true

              # Force a rescan so freshly-powered radios populate the
              # cache. Some drivers need a couple of seconds.
              nmcli device wifi rescan >/dev/null 2>&1 || true
              sleep 2

              # SSID picker. Loop so the user can rescan without
              # restarting the launcher.
              while true; do
                # SSID may contain spaces, so use a literal tab as the
                # nmcli terse separator. Strip empty / hidden SSIDs.
                mapfile -t lines < <(
                  nmcli -t -s -f IN-USE,SSID,SECURITY,SIGNAL device wifi list \
                    | awk -F: '$2 != "" && !seen[$2]++' \
                    | sort -t: -k4 -nr
                )

                if [ ''${#lines[@]} -eq 0 ]; then
                  kdialog --warningyesnocancel \
                    "No WiFi networks visible.\n\nYes = rescan, No = abort, Cancel = abort." \
                    && { nmcli device wifi rescan >/dev/null 2>&1 || true; sleep 2; continue; }
                  exit 0
                fi

                menu_args=("__rescan__" "[ Rescan networks ]")
                while IFS=: read -r in_use ssid sec signal; do
                  [ -n "$ssid" ] || continue
                  marker=" "
                  [ "$in_use" = "*" ] && marker="*"
                  menu_args+=("$ssid" "$marker $ssid  ($sec, $signal%)")
                done < <(printf '%s\n' "''${lines[@]}")

                SSID=$(kdialog --title "Connect WiFi" \
                  --menu "Select a network:" \
                  "''${menu_args[@]}") || exit 0

                if [ "$SSID" = "__rescan__" ]; then
                  nmcli device wifi rescan >/dev/null 2>&1 || true
                  sleep 2
                  continue
                fi
                break
              done

              # If the connection already exists (e.g. from a previous
              # successful connect), bring it up without re-prompting
              # for the password.
              if nmcli -t -f NAME connection show | grep -Fxq "$SSID"; then
                if up_out=$(nmcli connection up id "$SSID" 2>&1); then
                  kdialog --passivepopup "Reconnected to $SSID" 5
                  exit 0
                fi
                kdialog --sorry "Reconnect failed:\n\n$up_out\n\nWill prompt for password and re-create the connection."
                nmcli connection delete id "$SSID" >/dev/null 2>&1 || true
              fi

              # Password loop: re-prompt on empty input.
              while true; do
                PSK=$(kdialog --password "Password for \"$SSID\":") || exit 0
                if [ -z "$PSK" ]; then
                  kdialog --sorry "Password cannot be empty. Try again."
                  continue
                fi
                break
              done

              # Connect. nmcli writes the connection profile and
              # respects `[connection-defaults] psk-flags=0` so the PSK
              # lands in /etc/NetworkManager/system-connections, not in
              # any user secret store.
              if out=$(nmcli device wifi connect "$SSID" password "$PSK" 2>&1); then
                kdialog --passivepopup "Connected to $SSID" 5
              else
                kdialog --error "Connect failed:\n\n$out"
                exit 1
              fi
            '';
          };
        in
        {
          services.desktopManager.plasma6.enable = true;
          services.displayManager = {
            sddm.enable = true;
            sddm.wayland.enable = true;
            autoLogin = {
              enable = true;
              user = "nixos";
            };
            defaultSession = "plasma";
          };
          networking.hostName = "nixos-installer";

          # Use the latest mainline kernel so disko can format btrfs
          # with `compress=zstd:-1` (negative zstd levels require
          # kernel ≥ 6.15). nixpkgs' default LTS kernel is currently
          # 6.12.x which would reject the mount option.
          boot.kernelPackages = pkgs.linuxPackages_latest;

          # ZFS is marked broken on the latest kernel (no upstream
          # release tracking 7.x yet) and the installer doesn't need
          # it — drop ZFS from supportedFilesystems and skip building
          # the broken zfs-kernel module.
          boot.supportedFilesystems.zfs = lib.mkForce false;

          # OOM avoidance during disko-install: the live installer's
          # nix store is on a tmpfs overlay (squashfs is read-only),
          # so the entire target host's closure piles up in RAM
          # before disko has formatted the disk. Steam Deck has only
          # 16 GiB and the ali-steam-deck closure is multi-GiB →
          # the kernel OOM-kills disko-install partway through.
          # zram with zstd gives ~3× compression, so a 16 GiB zram
          # device costs ~5 GiB physical RAM and yields ~16 GiB of
          # extra virtual memory.
          zramSwap = {
            enable = true;
            algorithm = "zstd";
            memoryPercent = 100;
            priority = 100;
          };
          # Aggressively prefer compressed swap before OOM-killing.
          boot.kernel.sysctl."vm.swappiness" = 180;

          # Disable systemd-oomd on the installer. It uses PSI to
          # preemptively kill processes on memory-pressure spikes
          # ("Memory Shortage Avoided" notification), which has been
          # killing nix during the install. Let the kernel handle
          # real OOM — with 16 GiB RAM + 16 GiB zram and the install
          # now substituting directly to the target via
          # nixos-install --store /mnt, there should be no real
          # pressure to react to.
          systemd.oomd.enable = false;

          # Raise nofile system-wide so the sudo'd `nixos-install`
          # subprocess can substitute large closures without hitting
          # "Too many open files" — nix opens many .drv / NAR /
          # cache fds in parallel during substitution and the
          # default 1024 cap is far too tight for the multi-thousand
          # store paths in a desktop closure.
          security.pam.loginLimits = [
            { domain = "*"; type = "soft"; item = "nofile"; value = "1048576"; }
            { domain = "*"; type = "hard"; item = "nofile"; value = "1048576"; }
          ];

          # Grow the live nix-store tmpfs cap. The base ISO leaves
          # `/nix/.rw-store` (the overlay upperdir for /nix/store)
          # at the tmpfs default of 50% of RAM (~8 GiB on Steam
          # Deck). disko-install substitutes the target host's
          # closure into the LIVE store before formatting the disk,
          # which can ENOSPC on a multi-GiB closure. We override via
          # `lib.isoFileSystems` (the source `fileSystems` is read
          # from in `installation-cd-base.nix`); writing to
          # `fileSystems` directly is silently dropped because the
          # base sets the whole attrset via `mkImageMediaOverride`.
          # Pages spill to zramSwap under pressure, so a 16 GiB
          # tmpfs costs only ~5 GiB physical RAM at peak.
          lib.isoFileSystems."/nix/.rw-store" = lib.mkForce {
            fsType = "tmpfs";
            options = [ "mode=0755" "size=16G" ];
            neededForBoot = true;
          };
          lib.isoFileSystems."/" = lib.mkForce {
            fsType = "tmpfs";
            options = [ "mode=0755" "size=4G" ];
          };

          # NetworkManager: store WiFi PSKs as system-owned secrets
          # (`psk-flags=0`) in /etc/NetworkManager/system-connections
          # instead of in kwallet. The autologin `nixos` user has no
          # login password so kwallet's PAM auto-unlock can't open the
          # wallet, which causes plasma-nm to hang at "Waiting for
          # authorization" after credentials are entered. The
          # `connect-wifi` desktop launcher below is the recommended
          # path — it talks to NM directly via `nmcli` and bypasses
          # plasma-nm + kwallet entirely.
          # `installation-cd-graphical-base.nix` already enables NM and
          # `installation-device.nix` already adds the `nixos` user to
          # the `networkmanager`/`wheel` groups, so no extra user or
          # polkit config is required here.
          networking.networkmanager.settings.connection-defaults = {
            "802-11-wireless-security.psk-flags" = 0;
            "802-1x.password-flags" = 0;
          };

          # Timezone: pinned to Europe/London so KDE's clock shows the
          # right time out of the box. `timesyncd` is the NixOS default
          # but we set it explicitly so KDE finds an active NTP backend
          # without needing to toggle anything (the toggle was failing
          # with "file is read only" on the ROM-mounted ISO).
          time.timeZone = "Europe/London";
          services.timesyncd.enable = true;

          # On-screen keyboard for Steam Deck / touch installs.
          # InputMethod must be the absolute path to the .desktop file;
          # nixpkgs ships it as com.github.maliit.keyboard.desktop.
          # KWIN_IM_SHOW_ALWAYS=1 makes the OSK pop on focus for mouse/touch
          # both — without it KWin only auto-shows on touch events.
          environment.etc."xdg/kwinrc".text = ''
            [Wayland]
            VirtualKeyboardEnabled=true
            InputMethod=${pkgs.maliit-keyboard}/share/applications/com.github.maliit.keyboard.desktop
          '';
          environment.sessionVariables.KWIN_IM_SHOW_ALWAYS = "1";

          nix.settings = {
            experimental-features = [
              "nix-command"
              "flakes"
              "ca-derivations"
            ];
            trusted-users = [
              "root"
              "@wheel"
              "nixos"
            ];
            # Serialise builds so peak memory stays low. Almost
            # everything should substitute from cache anyway, but if
            # something does build, do it one-at-a-time (using all
            # cores per build via cores=0).
            max-jobs = 1;
            cores = 0;
          };

          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
              PermitRootLogin = "prohibit-password";
            };
          };

          users.users.nixos.openssh.authorizedKeys.keys = outputs.lib.sshKeys.all;
          users.users.root.openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];

          environment.systemPackages = [
            diskoPkg
          ] ++ (with pkgs; [
            git
            vim
            just
            maliit-keyboard
            installNixos
            connectWifi
            kdePackages.kdialog
            kdePackages.konsole
          ]);

          # Allow `sudo` without a password so the installer launcher can
          # run disko + nixos-install non-interactively.
          security.sudo.wheelNeedsPassword = lib.mkForce false;

          # Drop desktop launchers into the autologin user's Desktop
          # directory pointing at the install-nixos and connect-wifi
          # scripts.
          environment.etc."skel/Desktop/install-nixos.desktop" = {
            mode = "0755";
            text = ''
              [Desktop Entry]
              Type=Application
              Name=Install NixOS
              Comment=Run the NixOS installer for this flake
              Icon=system-software-install
              Exec=${pkgs.kdePackages.konsole}/bin/konsole --hold -e ${installNixos}/bin/install-nixos
              Terminal=false
              Categories=System;
            '';
          };
          environment.etc."skel/Desktop/connect-wifi.desktop" = {
            mode = "0755";
            text = ''
              [Desktop Entry]
              Type=Application
              Name=Connect WiFi
              Comment=Pick a WiFi network and connect via nmcli
              Icon=network-wireless
              Exec=${connectWifi}/bin/connect-wifi
              Terminal=false
              Categories=System;Network;
            '';
          };

          # Plasma 6 refuses to launch untrusted .desktop files. Pre-create
          # the Desktop directory and copy the launchers with executable
          # bit so Plasma renders them as clickable tiles. The user still
          # has to confirm "trust" once on first click.
          systemd.tmpfiles.rules = [
            "d /home/nixos/Desktop 0755 nixos users -"
            "C /home/nixos/Desktop/install-nixos.desktop 0755 nixos users - /etc/skel/Desktop/install-nixos.desktop"
            "C /home/nixos/Desktop/connect-wifi.desktop 0755 nixos users - /etc/skel/Desktop/connect-wifi.desktop"
          ];

          systemd.services.clone-nix-config = {
            description = "Clone nix-config and pre-fetch flake inputs on boot";
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [
              pkgs.git
              pkgs.openssh
              pkgs.cacert
              pkgs.nix
            ];
            serviceConfig = {
              Type = "oneshot";
              User = "nixos";
              Group = "users";
              WorkingDirectory = "/home/nixos";
              # Drop ConditionPathExists so re-runs (after a manual rm)
              # still pre-warm. If the repo exists we just skip the
              # clone step inline.
              Environment = [
                "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "HOME=/home/nixos"
                "NIX_CONFIG=experimental-features = nix-command flakes"
              ];
            };
            script = ''
              if [ ! -d /home/nixos/nix-config/.git ]; then
                git clone --depth 1 https://github.com/alisonjenkins/nix-config.git /home/nixos/nix-config
              fi
              # Pre-fetch flake inputs so the user-facing install-nixos
              # eval is near-instant. Non-fatal — a network blip just
              # means the user pays the fetch cost during install.
              cd /home/nixos/nix-config
              nix flake archive --json >/dev/null 2>&1 || true
            '';
          };

          image.fileName = lib.mkForce "nixos-installer-custom-${system}.iso";
        }
      )
    ];
  };
}
