set export

boot:
    #!/usr/bin/env bash
    if command -v nh &>/dev/null; then
        nh os boot .;
    elif [ "$(uname)" == "Darwin" ]; then
        darwin-rebuild boot --option sandbox false --flake .
    else
        sudo nixos-rebuild boot --flake ".#$HOST"
    fi

switch:
    #!/usr/bin/env bash
    if command -v nh &>/dev/null; then
        nh os switch .;
    elif [ "$(uname)" == "Darwin" ]; then
        darwin-rebuild switch --option sandbox false --flake .
    else
        sudo nixos-rebuild switch --flake ".#$HOST"
    fi

update:
    @nix flake update .

test-build hostname:
  #!/usr/bin/env bash
  CORES=$(nproc)
  nix build ".#nixosConfigurations.${hostname}.config.system.build.vm" --cores $CORES

test-run hostname:
  #!/usr/bin/env bash
  CORES=$(nproc)
  ./result/bin/run-${hostname}-vm \
    -accel kvm
    #-vga virtio
    #-display sdl,gl=on
  rm "${hostname}.qcow2"

alias b := boot
alias s := switch
alias u := update
