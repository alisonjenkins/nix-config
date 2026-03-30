# Builds a UEFI-bootable btrfs disk image for AWS AMI import.
#
# Strategy (SD card pattern):
#   1. Pre-VM: Build a standalone btrfs filesystem image via mkfs.btrfs -r
#   2. Pre-VM: Create a GPT-partitioned raw disk, dd the btrfs image into the root partition
#   3. VM:     Mount partitions, compress btrfs data with defragment, install bootloader
#   4. Post-VM: Convert to VHD, generate metadata
#
# This sidesteps the make-disk-image.nix limitation that partitioned images must use ext4.
{
  pkgs,
  lib,
  config,
  configFile ? null,
  contents ? [ ],
  format ? "vpc",
  baseName ? "nixos",
  diskSize ? "auto",
  additionalSpace ? "512M",
  bootSize ? "256M",
  postVM ? "",
  memSize ? 1024,
  copyChannel ? true,
  additionalPaths ? [ ],
}:

let
  filename = "${baseName}." + {
    qcow2 = "qcow2";
    vdi = "vdi";
    vpc = "vhd";
    raw = "img";
  }.${format} or format;

  nixpkgs = lib.cleanSource pkgs.path;

  channelSources = pkgs.runCommand "nixos-${config.system.nixos.version}" { } ''
    mkdir -p $out
    cp -prd ${nixpkgs.outPath} $out/nixos
    chmod -R u+w $out/nixos
    if [ ! -e $out/nixos/nixpkgs ]; then
      ln -s . $out/nixos/nixpkgs
    fi
    rm -rf $out/nixos/.git
    echo -n ${config.system.nixos.versionSuffix} > $out/nixos/.version-suffix
  '';

  basePaths = [ config.system.build.toplevel ] ++ lib.optional copyChannel channelSources;
  additionalPaths' = lib.subtractLists basePaths additionalPaths;

  closureInfo = pkgs.closureInfo {
    rootPaths = basePaths ++ additionalPaths';
  };

  sources = map (x: x.source) contents;
  targets = map (x: x.target) contents;
  modes = map (x: x.mode or "''") contents;
  users = map (x: x.user or "''") contents;
  groups = map (x: x.group or "''") contents;

  binPath = lib.makeBinPath (with pkgs; [
    rsync
    util-linux
    parted
    e2fsprogs
    btrfs-progs
    dosfstools
    config.system.build.nixos-install
    nixos-enter
    nix
    systemdMinimal
    gptfdisk
  ] ++ stdenv.initialPath);

  prepareImage = ''
    export PATH=${binPath}

    sectorsToBytes() {
      echo $(( "$1" * 512 ))
    }

    mebibyte=$(( 1024 * 1024 ))

    round_to_nearest() {
      echo $(( ( $1 / $2 + 1) * $2 ))
    }

    mkdir $out

    root="$PWD/root"
    mkdir -p $root

    # Copy arbitrary files into the staging root
    set -f
    sources_=(${lib.concatStringsSep " " sources})
    targets_=(${lib.concatStringsSep " " targets})
    modes_=(${lib.concatStringsSep " " modes})
    set +f

    for ((i = 0; i < ''${#targets_[@]}; i++)); do
      source="''${sources_[$i]}"
      target="''${targets_[$i]}"
      mode="''${modes_[$i]}"

      if [ -n "$mode" ]; then
        rsync_chmod_flags="--chmod=$mode"
      else
        rsync_chmod_flags=""
      fi
      rsync_flags="-a --no-o --no-g $rsync_chmod_flags"
      if [[ "$source" =~ '*' ]]; then
        mkdir -p $root/$target
        for fn in $source; do
          rsync $rsync_flags "$fn" $root/$target/
        done
      else
        mkdir -p $root/$(dirname $target)
        if [ -e $root/$target ]; then
          echo "duplicate entry $target -> $source"
          exit 1
        elif [ -d $source ]; then
          rsync $rsync_flags $source/ $root/$target
        else
          rsync $rsync_flags $source $root/$target
        fi
      fi
    done

    export HOME=$TMPDIR

    # Provide a Nix database so that nixos-install can copy closures.
    export NIX_STATE_DIR=$TMPDIR/state
    nix-store --load-db < ${closureInfo}/registration

    chmod 755 "$TMPDIR"
    echo "running nixos-install..."
    nixos-install --root $root --no-bootloader --no-root-passwd \
      --system ${config.system.build.toplevel} \
      ${if copyChannel then "--channel ${channelSources}" else "--no-channel-copy"} \
      --substituters ""

    ${lib.optionalString (additionalPaths' != []) ''
      nix --extra-experimental-features nix-command copy --to $root --no-check-sigs ${lib.concatStringsSep " " additionalPaths'}
    ''}

    # Install a configuration.nix in the staging root
    mkdir -p $root/etc/nixos
    ${lib.optionalString (configFile != null) ''
      cp ${configFile} $root/etc/nixos/configuration.nix
    ''}

    # === Build standalone btrfs root image ===
    echo "Creating btrfs filesystem image from staging root..."
    btrfsImage=btrfs-root.img

    # Calculate required size: actual data + headroom for btrfs metadata
    rootSize=$(du -sb $root | cut -f1)
    # btrfs metadata overhead ~5-10%, add 15% headroom to be safe
    btrfsSize=$(( rootSize + rootSize * 15 / 100 ))
    # Minimum 256 MiB for btrfs
    minSize=$(( 256 * mebibyte ))
    if [ $btrfsSize -lt $minSize ]; then
      btrfsSize=$minSize
    fi
    btrfsSize=$(round_to_nearest $btrfsSize $mebibyte)

    echo "  Root data size: $rootSize bytes"
    echo "  btrfs image size: $btrfsSize bytes"

    truncate -s $btrfsSize $btrfsImage
    mkfs.btrfs -L nixos -r $root --shrink $btrfsImage
    btrfs check $btrfsImage

    btrfsImageSize=$(stat -c%s $btrfsImage)
    echo "  btrfs image size after shrink: $btrfsImageSize bytes"

    # === Create GPT-partitioned disk ===
    diskImage=nixos.raw

    bootSize=$(round_to_nearest $(numfmt --from=iec '${bootSize}') $mebibyte)
    bootSizeMiB=$(( bootSize / 1024 / 1024 ))

    # GPT overhead at end of disk
    gptSpace=$(( 512 * 34 ))

    ${if diskSize == "auto" then ''
      # Root partition must fit the btrfs image + additional space for runtime writes
      additionalSpace=$(numfmt --from=iec '${additionalSpace}')
      rootPartSize=$(( btrfsImageSize + additionalSpace ))
      rootPartSize=$(round_to_nearest $rootPartSize $mebibyte)

      totalDiskSize=$(( bootSize + rootPartSize + gptSpace ))
      totalDiskSize=$(round_to_nearest $totalDiskSize $mebibyte)

      echo "  Boot partition: $bootSize bytes"
      echo "  Root partition: $rootPartSize bytes"
      echo "  Total disk size: $totalDiskSize bytes"

      truncate -s $totalDiskSize $diskImage
    '' else ''
      # Ensure the disk is at least large enough for the btrfs image + boot partition
      requestedSize=$(( ${toString diskSize} * mebibyte ))
      minDiskSize=$(( btrfsImageSize + bootSize + gptSpace ))
      minDiskSize=$(round_to_nearest $minDiskSize $mebibyte)
      if [ $requestedSize -lt $minDiskSize ]; then
        echo "  Requested disk size ($requestedSize bytes) too small for btrfs image, using $minDiskSize bytes"
        truncate -s $minDiskSize $diskImage
      else
        truncate -s ${toString diskSize}M $diskImage
      fi
    ''}

    # Partition: ESP (FAT32) + root (Linux filesystem)
    parted --script $diskImage -- \
      mklabel gpt \
      mkpart ESP fat32 8MiB ''${bootSizeMiB}MiB \
      set 1 boot on \
      align-check optimal 1 \
      mkpart primary btrfs ''${bootSizeMiB}MiB 100% \
      align-check optimal 2 \
      print

    # Set deterministic GUIDs
    sgdisk \
      --disk-guid=97FD5997-D90B-4AA3-8D16-C1723AEA73C \
      --partition-guid=1:1C06F03B-704E-4657-B9CD-681A087A2FDC \
      --partition-guid=2:F222513B-DED1-49FA-B591-20CE86A2FE7F \
      $diskImage

    # Write btrfs image into root partition via dd
    eval $(partx $diskImage -o START,SECTORS --nr 2 --pairs)
    echo "Writing btrfs image into partition 2 (start=$START sectors, size=$SECTORS sectors)..."
    dd conv=notrunc if=$btrfsImage of=$diskImage seek=$START obs=512 bs=512

    rm -f $btrfsImage
  '';

  moveOrConvertImage = ''
    ${if format == "raw" then ''
      mv $diskImage $out/${filename}
    '' else ''
      ${pkgs.qemu-utils}/bin/qemu-img convert -f raw -O ${format} $diskImage $out/${filename}
    ''}
    diskImage=$out/${filename}
  '';

  createHydraBuildProducts = ''
    mkdir -p $out/nix-support
    echo "file ${format}-image $out/${filename}" >> $out/nix-support/hydra-build-products
  '';

in
pkgs.vmTools.runInLinuxVM (
  pkgs.runCommand baseName
    {
      preVM = prepareImage;
      buildInputs = with pkgs; [
        util-linux
        e2fsprogs
        btrfs-progs
        dosfstools
        parted
      ];
      postVM = moveOrConvertImage + createHydraBuildProducts + postVM;
      inherit memSize;
    }
    ''
      export PATH=${binPath}:$PATH

      # make systemd-boot find ESP without udev
      mkdir -p /dev/block
      ln -s /dev/vda1 /dev/block/254:1

      mountPoint=/mnt
      mkdir -p $mountPoint

      # Resize btrfs to fill the partition (it was shrunk by mkfs --shrink)
      # We need to mount first, then resize, since btrfs resize is online-only
      mount -t btrfs /dev/vda2 $mountPoint
      btrfs filesystem resize max $mountPoint

      # Compress all existing data in-place with zstd
      echo "Compressing btrfs data with zstd..."
      btrfs filesystem defragment -r -czstd $mountPoint
      sync

      echo "btrfs filesystem usage:"
      btrfs filesystem usage $mountPoint || true

      # Create and mount ESP
      mkdir -p $mountPoint/boot
      mkfs.vfat -n ESP /dev/vda1
      mount /dev/vda1 $mountPoint/boot

      # Install bootloader
      export HOME=$TMPDIR
      NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root $mountPoint -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot

      # Set ownerships for contents
      targets_=(${lib.concatStringsSep " " targets})
      users_=(${lib.concatStringsSep " " users})
      groups_=(${lib.concatStringsSep " " groups})
      for ((i = 0; i < ''${#targets_[@]}; i++)); do
        target="''${targets_[$i]}"
        user="''${users_[$i]}"
        group="''${groups_[$i]}"
        if [ -n "$user$group" ]; then
          nixos-enter --root $mountPoint -- chown -R "$user:$group" "$target"
        fi
      done

      umount -R /mnt
    ''
)
