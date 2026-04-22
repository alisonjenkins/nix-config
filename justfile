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

# One-time bootstrap of rclone bisync state for claude-sync.
# Run this on each machine after the module is first enabled and the
# secrets/claude-sync.enc.yaml secret is populated. It pauses the timer,
# seeds bisync against the remote, then restarts the timer.
claude-sync-bootstrap:
    claude-sync-bootstrap

alias b := boot
alias B := build
alias s := switch
alias t := test
alias u := update
