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
        nh os test --hostname "$(hostname)" . -- {{extraargs}} ;
    elif [ "$(uname)" == "Darwin" ]; then
        darwin-rebuild test --option sandbox false {{extraargs}} --flake .
    else
        rm -f ~/.gtkrc-2.0
        sudo nixos-rebuild test {{extraargs}} --flake ".#$HOST"
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
        nh os switch --hostname "$(hostname)" . -- {{extraargs}} ;
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
  ./result/bin/run-${hostname}-vm \
    -accel kvm
    #-vga virtio
    #-display sdl,gl=on
  rm "${hostname}.qcow2"

# Update flake
update:
    #!/usr/bin/env bash
    export NIX_CONFIG="access-tokens = github.com=$(op item get "Github PAT" --fields label=password --reveal --cache)"
    nix flake update --commit-lock-file

alias b := boot
alias s := switch
alias t := test
alias u := update
