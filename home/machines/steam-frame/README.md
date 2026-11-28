# Steam Frame (standalone home-manager)

`homeConfigurations.steamos` (`flake-modules/hosts/home-only`): the Valve
Steam Frame's `steamos` user on SteamOS (aarch64-linux, read-only root).
Home config: this directory. Frame-specific fixes come from
[lhns/steam-frame-nix](https://github.com/lhns/steam-frame-nix)
(`steamFrame.*` options); the rest is a terminal-focused subset of
`home/programs` (zsh, tmux, nvim, git, gh, ssh, direnv, fzf, zoxide, ...).
It deliberately does not import `home-linux` (niri, stylix, x86-only apps).

All steps run in Konsole in the Frame's nested desktop, not over SSH into
the Frame and not in the Steam session: switching there lets clipboard-sync
restart with the desktop's environment (steam-frame-nix README, "Two
sessions").

## First install

1. Check the user name is `steamos` (`id -un`): steam-frame-nix's
   installer and `just switch` both pick `homeConfigurations.<user>`. If it
   isn't, clone first, set `frameUsername` in
   `flake-modules/hosts/home-only/default.nix`, `git commit` it, and in
   step 3 pass `--flake ~/nix-config` instead of `--clone ...`:

   ```sh
   git clone https://github.com/alisonjenkins/nix-config ~/nix-config
   ```
2. `passwd` if no password is set yet (the installer needs `sudo` to put
   Nix on the read-only root).
3. Install Nix and switch to this repo in one go. The repo is public, so
   HTTPS needs no credentials:

   ```sh
   curl -fsSL https://steam-frame-nix.lhns.de | bash -s -- install \
     --clone https://github.com/alisonjenkins/nix-config
   ```

   Add `--ref <branch>` to install from a branch that isn't merged yet.
   It clones into `~/nix-config`, links `~/.config/home-manager` to it and
   runs `home-manager switch` (dotfiles in the way become
   `*.hm-backup-<time>`). The first switch builds clipboard-sync from source
   and fetches nvim, so give it a while on mains power.
4. Reboot once when the installer ends with "Restart once" (keyboard layout
   and the SteamVR dashboard patches are read at process start).
5. Open a new Konsole: bash hands over to zsh (set `NO_ZSH=1` to stay in
   bash).

## SSH key (Frame -> ali-desktop)

There is no 1Password agent on the Frame (`sshUse1Password = false`), so the
Frame has its own key and every SSH host stanza uses `~/.ssh/id_ed25519`:

```sh
ssh-keygen -t ed25519 -C steam-frame -f ~/.ssh/id_ed25519
ssh-add ~/.ssh/id_ed25519   # agent runs in the Steam session; shared by both sessions
cat ~/.ssh/id_ed25519.pub
```

Then authorise the public key on ali-desktop: add it as `steamFrame` in
`flake-modules/lib.nix` (`flake.lib.sshKeys`), append it to `ali-desktop`'s
`users.users.ali.openssh.authorizedKeys.keys`, and `just switch` there.
Optionally add it to GitHub too, for pushes from the headset. The
installer cloned over HTTPS, so point pushes at SSH:

```sh
git -C ~/nix-config remote set-url --push origin git@github.com:alisonjenkins/nix-config.git
```

After that,
`ssh ali-desktop.lan` (or `ali-desktop` via Tailscale, if the Frame joins
the tailnet) works.

## Updating

```sh
cd ~/nix-config && git pull && just switch
```

`just switch` runs `home-manager switch --flake .#$(id -un)` on any
non-NixOS machine. To go back: `home-manager generations`, then run the
`activate` script of an older one. steam-frame-nix's own undo for what it
writes outside the store: `nix run github:lhns/steam-frame-nix#cleanup -- --all`.
