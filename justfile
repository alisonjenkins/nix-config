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

test *extraargs:
    #!/usr/bin/env bash
    if command -v nh &>/dev/null; then
        nh os test .;
    elif [ "$(uname)" == "Darwin" ]; then
        darwin-rebuild test --option sandbox false {{extraargs}} --flake .
    else
        sudo nixos-rebuild test {{extraargs}} --flake ".#$HOST"
    fi

switch *extraargs:
    #!/usr/bin/env bash
    if command -v nh &>/dev/null; then
        nh os switch .;
    elif [ "$(uname)" == "Darwin" ]; then
        darwin-rebuild switch --option sandbox false --flake . {{extraargs}}
    else
        sudo nixos-rebuild switch --flake ".#$HOST" {{extraargs}}
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
alias t := test
alias u := update
