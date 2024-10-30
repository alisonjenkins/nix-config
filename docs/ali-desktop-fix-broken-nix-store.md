# Fix broken Nix store on ali-desktop

1. Boot into NixOS live disk
2. Switch to root using `sudo -i`
3. Mount the volumes using:

```bash
cryptsetup luksOpen /dev/disk/by-partlabel/osvg -
mkdir -p /mnt/nix /mnt/persistence /mnt/home
mount -o subvol=nix /dev/osvg/persistence /mnt/nix
mount -o subvol=persistence /dev/osvg/persistence /mnt/persistence
```

4. Clone the repo and re-install
```bash
git clone https://github.com/alisonjenkins/nix-config
nixos-install --flake '.#ali-desktop'
```
