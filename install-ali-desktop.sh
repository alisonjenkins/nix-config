#!/usr/bin/env bash
if [ -e "$HOME/.config/gtk-3.0" ]; then
	rm -f "$HOME/.config/gtk-3.0/settings.ini"
fi

if [ -e "$HOME/.config/gtk-4.0" ]; then
	rm -f "$HOME/.config/gtk-4.0/settings.ini"
fi

DIR=$(pwd)
cp -f /etc/nixos/hardware-configuration.nix "$DIR"/nixos/

if [ ! -f ~/Pictures/wallpapers/menhera.jpg ]; then
	mkdir -p ~/Pictures/wallpapers/

	cp "$DIR"/home/wallpapers/wallpaper.png ~/Pictures/wallpapers/
fi
if [ ! -f ~/.config/rofi/rofi.png ]; then
	mkdir -p ~/Pictures/wallpapers/

	cp "$DIR"/home/wallpapers/rofi.png ~/.config/rofi/
fi

sudo nixos-rebuild switch --flake .#ali --show-trace
