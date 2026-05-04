set export

# List justfile targets
list:
    @just --list

# Build the config this system and switch on next boot
boot:
    #!/usr/bin/env bash
    if command -v nh &>/dev/null; then
        rm -f ~/.gtkrc-2.0
        nh os boot .;
    elif [ "$(uname)" == "Darwin" ]; then
        darwin-rebuild boot --option sandbox false --flake .
    else
        rm -f ~/.gtkrc-2.0
        sudo nixos-rebuild boot --flake ".#$HOST"
    fi

# Build the config for this system and activate it but only temporarily
test *extraargs:
    #!/usr/bin/env bash
    if command -v nh &>/dev/null; then
        rm -f ~/.gtkrc-2.0
        nh os test . -- {{extraargs}} ;
    elif [ "$(uname)" == "Darwin" ]; then
        sudo darwin-rebuild test --option sandbox false {{extraargs}} --flake .
    else
        rm -f ~/.gtkrc-2.0
        sudo nixos-rebuild test {{extraargs}} --flake ".#$HOST"
    fi

# Build the config for this system without activating it
build hostname="" *extraargs:
    #!/usr/bin/env bash
    reset_power_profile() {
        powerprofilesctl set "$PRE_POWER_PROFILE"
    }

    if command -v powerprofilesctl &>/dev/null; then
        export PRE_POWER_PROFILE=$(powerprofilesctl get)
        powerprofilesctl set performance
        trap reset_power_profile EXIT
    fi

    TARGET_HOST="{{hostname}}"
    if [ -z "$TARGET_HOST" ]; then
        TARGET_HOST="$(hostname)"
    fi

    if command -v nh &>/dev/null; then
        rm -f ~/.gtkrc-2.0
        nh os build --hostname "$TARGET_HOST" . -- {{extraargs}} ;
    elif [ "$(uname)" == "Darwin" ]; then
        darwin-rebuild build --option sandbox false --flake ".#$TARGET_HOST" {{extraargs}}
    else
        rm -f ~/.gtkrc-2.0
        sudo nixos-rebuild build --flake ".#$TARGET_HOST" {{extraargs}}
    fi

# Build a host's system closure locally and ship it to a remote
# install-iso target whose nix store lives at /mnt, then run
# nixos-install on the remote to write bootloader + /etc.
# Use when the target machine's CPU is too slow to build (e.g. Steam Deck).
# Defaults match installing ali-steam-deck from a fast machine on the LAN.
install-remote hostname="ali-steam-deck" target="root@192.168.1.67":
    #!/usr/bin/env bash
    set -euo pipefail

    # SSH options: force the primary key + 1Password agent. Needed
    # because the user's ~/.ssh/config sets `IdentitiesOnly yes`
    # without a default IdentityFile, so agent keys aren't offered
    # to ad-hoc hosts unless we name one explicitly here.
    SSH_OPTS=(
      -o IdentitiesOnly=yes
      -o IdentityFile="$HOME/.ssh/id_personal.pub"
      -o IdentityAgent="$HOME/.1password/agent.sock"
      -o StrictHostKeyChecking=accept-new
    )
    export NIX_SSHOPTS="${SSH_OPTS[*]}"

    echo "==> Building .#{{hostname}} locally"
    storepath=$(nix build --no-link --print-out-paths \
      ".#nixosConfigurations.{{hostname}}.config.system.build.toplevel")
    echo "    closure: $storepath"

    echo "==> Copying closure to {{target}}:/mnt/nix"
    nix copy --no-check-sigs \
      --to "ssh-ng://{{target}}?remote-store=local%3Froot%3D%2Fmnt" \
      "$storepath"

    echo "==> Running nixos-install on {{target}}"
    ssh "${SSH_OPTS[@]}" "{{target}}" \
      "nixos-install --root /mnt --no-root-passwd --no-channel-copy --system $storepath"

# Build the config for this system and activate it
switch *extraargs:
    #!/usr/bin/env bash
    reset_power_profile() {
        powerprofilesctl set "$PRE_POWER_PROFILE"
    }

    if command -v powerprofilesctl &>/dev/null; then
        export PRE_POWER_PROFILE=$(powerprofilesctl get)
        powerprofilesctl set performance
        trap reset_power_profile EXIT
    fi

    if command -v nh &>/dev/null; then
        rm -f ~/.gtkrc-2.0
        nh os switch . -- {{extraargs}} ;
    elif [ "$(uname)" == "Darwin" ]; then
        sudo darwin-rebuild switch --option sandbox false --flake . {{extraargs}}
    else
        rm -f ~/.gtkrc-2.0
        sudo nixos-rebuild switch --flake ".#$HOST" {{extraargs}}
    fi

# Use Deploy-RS to build and deploy to other machines
deploy *extraargs:
    #!/usr/bin/env bash
    reset_power_profile() {
        powerprofilesctl set "$PRE_POWER_PROFILE"
    }

    if command -v powerprofilesctl &>/dev/null; then
        export PRE_POWER_PROFILE=$(powerprofilesctl get)
        powerprofilesctl set performance
        trap reset_power_profile EXIT
    fi

    deploy {{extraargs}}

# Build the specified system as a VM
test-build hostname:
  #!/usr/bin/env bash
  CORES=$(nproc)
  nix build ".#nixosConfigurations.${hostname}.config.system.build.vm" --cores $CORES

# Run a built VM for the system
test-run hostname:
  #!/usr/bin/env bash
  CORES=$(nproc)
  # Handle VM variants that have different binary names
  if [ -f "./result/bin/run-${hostname}-vm" ]; then
    ./result/bin/run-${hostname}-vm
  elif [ -f "./result/bin/run-${hostname}" ]; then
    ./result/bin/run-${hostname}
  else
    echo "Error: Could not find VM binary for ${hostname}"
    ls -la ./result/bin/
    exit 1
  fi
  rm "${hostname}.qcow2" 2>/dev/null || true

# Update flake
update:
    #!/usr/bin/env bash
    export NIX_CONFIG="access-tokens = github.com=$(op item get "Github PAT" --fields label=password --reveal --cache)"
    nix flake update --commit-lock-file

# Build an AMI image
ami-build hostname:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building AMI for {{hostname}}..."
    nix build ".#{{hostname}}-ami" --print-out-paths
    echo ""
    echo "Image info:"
    cat result/nix-support/image-info.json | jq .

# Upload a built AMI to AWS
ami-upload hostname region="eu-west-2" bucket="nixos-amis":
    #!/usr/bin/env bash
    set -euo pipefail

    RESULT="./result"
    if [ ! -d "$RESULT/nix-support" ]; then
        echo "Error: No built AMI found. Run 'just ami-build {{hostname}}' first."
        exit 1
    fi

    # Find the VHD file
    VHD=$(find "$RESULT" -name "*.vhd" | head -1)
    if [ -z "$VHD" ]; then
        echo "Error: No VHD file found in $RESULT"
        exit 1
    fi

    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    S3_KEY="{{hostname}}/${TIMESTAMP}/$(basename "$VHD")"

    echo "Uploading $VHD to s3://{{bucket}}/$S3_KEY..."
    aws s3 cp "$VHD" "s3://{{bucket}}/$S3_KEY" --region {{region}}

    echo "Importing EBS snapshot..."
    IMPORT_TASK=$(aws ec2 import-snapshot \
        --region {{region}} \
        --description "NixOS AMI {{hostname}} ${TIMESTAMP}" \
        --disk-container "Format=VHD,UserBucket={S3Bucket={{bucket}},S3Key=$S3_KEY}" \
        --output json)

    TASK_ID=$(echo "$IMPORT_TASK" | jq -r '.ImportTaskId')
    echo "Import task: $TASK_ID"

    echo "Waiting for snapshot import to complete..."
    while true; do
        STATUS=$(aws ec2 describe-import-snapshot-tasks \
            --region {{region}} \
            --import-task-ids "$TASK_ID" \
            --output json)

        PROGRESS=$(echo "$STATUS" | jq -r '.ImportSnapshotTasks[0].SnapshotTaskDetail.Progress // "0"')
        STATE=$(echo "$STATUS" | jq -r '.ImportSnapshotTasks[0].SnapshotTaskDetail.Status')

        echo "  Status: $STATE ($PROGRESS%)"

        if [ "$STATE" = "completed" ]; then
            SNAPSHOT_ID=$(echo "$STATUS" | jq -r '.ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId')
            break
        elif [ "$STATE" = "error" ]; then
            echo "Error: Snapshot import failed"
            echo "$STATUS" | jq '.ImportSnapshotTasks[0].SnapshotTaskDetail'
            exit 1
        fi

        sleep 15
    done

    echo "Snapshot: $SNAPSHOT_ID"

    # Read architecture and boot mode from image-info.json
    IMAGE_INFO="$RESULT/nix-support/image-info.json"
    SYSTEM=$(jq -r '.system // "x86_64-linux"' "$IMAGE_INFO")
    BOOT_MODE=$(jq -r '.boot_mode // "uefi"' "$IMAGE_INFO")
    case "$SYSTEM" in
        aarch64-*) ARCH="arm64" ;;
        *)         ARCH="x86_64" ;;
    esac

    AMI_NAME="nixos-{{hostname}}-${TIMESTAMP}"

    echo "Registering AMI: $AMI_NAME (arch=$ARCH, boot=$BOOT_MODE)..."
    AMI_ID=$(aws ec2 register-image \
        --region {{region}} \
        --name "$AMI_NAME" \
        --description "NixOS AMI {{hostname}}" \
        --architecture "$ARCH" \
        --root-device-name /dev/xvda \
        --block-device-mappings "DeviceName=/dev/xvda,Ebs={SnapshotId=$SNAPSHOT_ID,VolumeType=gp3}" \
        --virtualization-type hvm \
        --boot-mode "$BOOT_MODE" \
        --ena-support \
        --output text --query 'ImageId')

    echo ""
    echo "AMI registered successfully!"
    echo "  AMI ID: $AMI_ID"
    echo "  Region: {{region}}"
    echo "  Name:   $AMI_NAME"

# Build and upload an AMI in one step
ami hostname region="eu-west-2" bucket="nixos-amis":
    just ami-build {{hostname}}
    just ami-upload {{hostname}} {{region}} {{bucket}}

# Build a NixOS installer ISO (defaults to the customised installer-iso host)
iso hostname="installer-iso":
    #!/usr/bin/env bash
    set -euo pipefail
    nix build ".#nixosConfigurations.{{hostname}}.config.system.build.isoImage"
    ls -lh result/iso/

# Build the Create Sky Colonies Minecraft server OCI image (single arch).
# Defaults to host arch; pass "amd64" or "arm64" to cross-build.
mc-build arch="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{arch}}" in
        amd64|x86_64) sys="x86_64-linux" ;;
        arm64|aarch64) sys="aarch64-linux" ;;
        "") sys="$(nix eval --impure --raw --expr 'builtins.currentSystem')" ;;
        *) echo "unknown arch: {{arch}} (use amd64|arm64)"; exit 1 ;;
    esac
    case "$sys" in
        *-linux) ;;
        *) echo "host system $sys cannot build linux containers without a remote linux builder"; exit 1 ;;
    esac
    nix build ".#packages.$sys.minecraft-csc-image" --print-out-paths

# Build BOTH arches and push as a multi-arch manifest.
# Requires `skopeo` (handles gzipped docker-archive) and `crane`
# (for `index append`). Registry creds: ~/.docker/config.json or
# the registry-specific env vars skopeo/crane support.
# Usage: just mc-push ghcr.io/alisonjenkins/create-sky-colonies v1.05
mc-push image tag:
    #!/usr/bin/env bash
    set -euo pipefail

    # Tools fetched via nix run so the recipe works without entering the
    # dev shell. skopeo handles gzipped docker-archive; crane handles
    # the multi-arch index assembly.
    skopeo() { nix run nixpkgs#skopeo -- "$@"; }
    crane() { nix run nixpkgs#go-containerregistry -- "$@"; }

    # skopeo writes auth to ~/.config/containers/auth.json by default;
    # crane reads ~/.docker/config.json. Bridge them by exposing skopeo's
    # auth file as a docker config in a temp DOCKER_CONFIG dir so crane
    # sees the registry credentials we just established.
    if [ -f "$HOME/.config/containers/auth.json" ]; then
        export DOCKER_CONFIG="$(mktemp -d)"
        trap 'rm -rf "$DOCKER_CONFIG"' EXIT
        ln -s "$HOME/.config/containers/auth.json" "$DOCKER_CONFIG/config.json"
    fi

    echo "==> Building amd64 image"
    amd64_tar=$(nix build --no-link --print-out-paths \
      '.#packages.x86_64-linux.minecraft-csc-image')
    echo "==> Building arm64 image"
    arm64_tar=$(nix build --no-link --print-out-paths \
      '.#packages.aarch64-linux.minecraft-csc-image')

    echo "==> Pushing amd64 layer"
    skopeo --insecure-policy copy "docker-archive:$amd64_tar" "docker://{{image}}:{{tag}}-amd64"
    echo "==> Pushing arm64 layer"
    skopeo --insecure-policy copy "docker-archive:$arm64_tar" "docker://{{image}}:{{tag}}-arm64"

    echo "==> Creating multi-arch manifest"
    crane index append \
        -m "{{image}}:{{tag}}-amd64" \
        -m "{{image}}:{{tag}}-arm64" \
        -t "{{image}}:{{tag}}"

    echo ""
    echo "Pushed: {{image}}:{{tag}}"
    crane manifest "{{image}}:{{tag}}" | head -40

# Build the Create: Arkana + Aeronautics server OCI image (single arch).
# Defaults to host arch; pass "amd64" or "arm64" to cross-build.
arkana-build arch="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{arch}}" in
        amd64|x86_64) sys="x86_64-linux" ;;
        arm64|aarch64) sys="aarch64-linux" ;;
        "") sys="$(nix eval --impure --raw --expr 'builtins.currentSystem')" ;;
        *) echo "unknown arch: {{arch}} (use amd64|arm64)"; exit 1 ;;
    esac
    case "$sys" in
        *-linux) ;;
        *) echo "host system $sys cannot build linux containers without a remote linux builder"; exit 1 ;;
    esac
    nix build ".#packages.$sys.minecraft-arkana-aeronautics-image" --print-out-paths

# Build BOTH arches and push as a multi-arch manifest.
# Mirrors `mc-push` shape: skopeo for per-arch push, crane for manifest list.
# Tag is the IMAGE tag (`v1.5-aero-1.2.1-7`), NOT the git tag.
# Usage: just arkana-push v1.5-aero-1.2.1-7
arkana-push tag image="ghcr.io/alisonjenkins/create-arkana-aeronautics-server":
    #!/usr/bin/env bash
    set -euo pipefail

    skopeo() { nix run nixpkgs#skopeo -- "$@"; }
    crane()  { nix run nixpkgs#go-containerregistry -- "$@"; }

    # skopeo auth file → docker config bridge (same dance as mc-push).
    if [ -f "$HOME/.config/containers/auth.json" ]; then
        export DOCKER_CONFIG="$(mktemp -d)"
        trap 'rm -rf "$DOCKER_CONFIG"' EXIT
        ln -s "$HOME/.config/containers/auth.json" "$DOCKER_CONFIG/config.json"
    fi

    echo "==> Building amd64 image"
    amd64_tar=$(nix build --no-link --print-out-paths \
      '.#packages.x86_64-linux.minecraft-arkana-aeronautics-image')
    echo "==> Building arm64 image"
    arm64_tar=$(nix build --no-link --print-out-paths \
      '.#packages.aarch64-linux.minecraft-arkana-aeronautics-image')

    echo "==> Pushing {{image}}:{{tag}}-amd64"
    skopeo --insecure-policy copy "docker-archive:$amd64_tar" "docker://{{image}}:{{tag}}-amd64"
    echo "==> Pushing {{image}}:{{tag}}-arm64"
    skopeo --insecure-policy copy "docker-archive:$arm64_tar" "docker://{{image}}:{{tag}}-arm64"

    echo "==> Creating multi-arch manifest {{image}}:{{tag}}"
    crane index append \
        -m "{{image}}:{{tag}}-amd64" \
        -m "{{image}}:{{tag}}-arm64" \
        -t "{{image}}:{{tag}}"

    echo "==> Updating multi-arch manifest {{image}}:latest"
    crane index append \
        -m "{{image}}:{{tag}}-amd64" \
        -m "{{image}}:{{tag}}-arm64" \
        -t "{{image}}:latest"

    echo ""
    echo "Pushed: {{image}}:{{tag}} ({{image}}:latest)"
    crane manifest "{{image}}:{{tag}}" | head -40

# Push ONLY the aarch64 image and assemble the multi-arch manifest list.
# Use after CI has pushed `:tag-amd64` (release workflow does this on tag
# push). Avoids wasting bandwidth + builder time re-pushing the amd64
# layer the runner already shipped.
# Tag is the IMAGE tag (`v1.5-aero-1.2.1-7`), NOT the git tag.
# Usage: just arkana-publish-arm64 v1.5-aero-1.2.1-7
arkana-publish-arm64 tag image="ghcr.io/alisonjenkins/create-arkana-aeronautics-server":
    #!/usr/bin/env bash
    set -euo pipefail

    skopeo() { nix run nixpkgs#skopeo -- "$@"; }
    crane()  { nix run nixpkgs#go-containerregistry -- "$@"; }

    if [ -f "$HOME/.config/containers/auth.json" ]; then
        export DOCKER_CONFIG="$(mktemp -d)"
        trap 'rm -rf "$DOCKER_CONFIG"' EXIT
        ln -s "$HOME/.config/containers/auth.json" "$DOCKER_CONFIG/config.json"
    fi

    # Assert the amd64 layer is already in the registry — fail fast with
    # a clear message instead of producing a single-arch manifest list.
    echo "==> Verifying {{image}}:{{tag}}-amd64 is published"
    if ! crane manifest "{{image}}:{{tag}}-amd64" >/dev/null 2>&1; then
        echo "ERROR: {{image}}:{{tag}}-amd64 is missing — is the GHA release workflow finished?" >&2
        echo "       Run 'gh run list --workflow=arkana-aeronautics-release.yaml' to check." >&2
        exit 1
    fi

    echo "==> Building arm64 image (via linux remote builder)"
    arm64_tar=$(nix build --no-link --print-out-paths \
      '.#packages.aarch64-linux.minecraft-arkana-aeronautics-image')

    echo "==> Pushing {{image}}:{{tag}}-arm64"
    skopeo --insecure-policy copy "docker-archive:$arm64_tar" "docker://{{image}}:{{tag}}-arm64"

    echo "==> Creating multi-arch manifest {{image}}:{{tag}}"
    crane index append \
        -m "{{image}}:{{tag}}-amd64" \
        -m "{{image}}:{{tag}}-arm64" \
        -t "{{image}}:{{tag}}"

    echo "==> Updating multi-arch manifest {{image}}:latest"
    crane index append \
        -m "{{image}}:{{tag}}-amd64" \
        -m "{{image}}:{{tag}}-arm64" \
        -t "{{image}}:latest"

    echo ""
    echo "Multi-arch published: {{image}}:{{tag}} + {{image}}:latest"
    crane manifest "{{image}}:{{tag}}" | head -40

alias b := boot
alias B := build
alias s := switch
alias t := test
alias u := update
