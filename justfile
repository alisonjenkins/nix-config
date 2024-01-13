set export

switch:
    #!/usr/bin/env bash
    if command -v nh &>/dev/null; then
        nh os switch .;
    fi
    sudo nixos-rebuild switch --flake ".#$HOST"

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

alias s := switch
alias u := update
