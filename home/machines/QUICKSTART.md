# Quick Start Guide

This is a condensed setup guide. For detailed documentation, see [README.md](README.md).

## 1. Get Your Location Data

```bash
# Get monitor EDID hashes
detect-location --show-monitors

# Get visible WiFi networks
detect-location --show-wifi
```

## 2. Create Location Config

```bash
# Copy template
cp ~/git/personal/nix-config/home/machines/locations.yaml.template /tmp/locations-$(hostname).yaml

# Edit with your data
$EDITOR /tmp/locations-$(hostname).yaml

# Example content:
cat > /tmp/locations-$(hostname).yaml <<'EOF'
locations:
  - name: home
    wifi_networks:
      - "YourHomeWiFi"
    monitor_edids:
      - "your-monitor-edid-hash"

  - name: work
    wifi_networks:
      - "WorkWiFi"
EOF
```

## 3. Set Up SOPS (First Time Only)

```bash
# Generate age key (if not already done)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Get public key
age-keygen -y ~/.config/sops/age/keys.txt
# Copy the output (starts with age1...)

# Add to .sops.yaml in repo
# Add your machine's entry following existing pattern
```

## 4. Encrypt and Deploy

```bash
HOSTNAME=$(hostname)

# Copy to secrets directory
cp /tmp/locations-$HOSTNAME.yaml ~/git/personal/nix-config/secrets/$HOSTNAME/locations.yaml

# Encrypt
cd ~/git/personal/nix-config
sops -e -i secrets/$HOSTNAME/locations.yaml

# Verify encryption (should show "sops:" and encrypted data)
head secrets/$HOSTNAME/locations.yaml

# Rebuild system
just switch
```

## 5. Test

```bash
# Test location detection
detect-location --verbose

# Test audio context
audio-context-volume --location home --verbose

# Check service status
systemctl --user status audio-context-boot.service
systemctl status audio-context-pre-suspend.service
systemctl status audio-context-resume.service
```

## Common Commands

```bash
# Show current location
detect-location

# Show monitors and WiFi
detect-location --show-monitors
detect-location --show-wifi

# Test audio volumes
audio-context-volume --location home --verbose

# Watch service logs
journalctl --user -u audio-context-boot.service -f
journalctl -u audio-context-pre-suspend.service -f

# Manually trigger services
systemctl --user start audio-context-boot.service
sudo systemctl start audio-context-pre-suspend.service
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Location always "unknown" | Check `detect-location --show-monitors --show-wifi` matches config |
| Config not found | Verify `~/.config/location-detection/locations.yaml` exists |
| Volumes not changing | Check `systemctl --user status audio-context-boot.service` |
| Suspend hooks not working | Check `systemctl status audio-context-pre-suspend.service` |
| PulseAudio errors | Check `systemctl --user status pipewire.service` |

## File Locations

- Location config (encrypted): `secrets/<hostname>/locations.yaml`
- Location config (deployed): `~/.config/location-detection/locations.yaml`
- Audio rules config: `home/machines/<hostname>/audio-context/default.nix`
- EasyEffects profiles: `home/machines/<hostname>/easyeffects/profiles/*.json`

## Important Notes

⚠️ **NEVER commit unencrypted locations.yaml** - WiFi networks reveal your location!

✓ Always encrypt with SOPS before committing

✓ Test location detection after encrypting

✓ Rebuild system with `just switch` after changes

For full documentation, see [README.md](README.md).
