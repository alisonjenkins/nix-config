# Per-Machine Configuration Guide

This directory contains per-machine home-manager configurations for desktop systems, providing context-aware audio management and EasyEffects profiles.

## Features

- **Location Detection**: Identifies your current location based on visible WiFi networks and connected monitor EDIDs
- **Context-Aware Volume Management**: Automatically adjusts speaker and microphone volumes based on location
- **EasyEffects Profiles**: Per-machine audio effect profiles that deploy automatically
- **Suspend/Resume Hooks**: Mutes speakers before suspend and applies location-appropriate volumes on resume

## Directory Structure

```
home/machines/<hostname>/
├── default.nix                    # Imports all modules
├── location-detection/
│   └── default.nix               # Location detection configuration
├── audio-context/
│   └── default.nix               # Volume rules and systemd services
└── easyeffects/
    ├── default.nix               # EasyEffects configuration
    └── profiles/                 # JSON profile files (.gitkeep placeholder)
```

## Setup Guide

### 1. Location Detection Setup

Location detection uses a combination of visible WiFi networks and connected monitor EDIDs to determine where you are.

#### Step 1: Gather Location Data

**Find Monitor EDID Hashes:**
```bash
detect-location --show-monitors
```

Example output:
```
Current Monitor EDID Hashes:
============================
  a8f3e2d1c9b5a7f6e4d2c1b9a8f7e6d5
  b9e4f3d2c1a8b7e6f5d4c3b2a1e9f8d7
```

**Find Visible WiFi Networks:**
```bash
detect-location --show-wifi
```

Example output:
```
Visible WiFi Networks:
======================
  HomeNetwork5G
  HomeNetwork2.4G
  OfficeWiFi
  CoffeeShopGuest
```

#### Step 2: Create Location Configuration

Create a plain-text YAML file for your machine. You can create it anywhere temporarily:

```bash
# Create temporary location config
cat > /tmp/locations-ali-desktop.yaml <<'EOF'
locations:
  - name: home
    wifi_networks:
      - "HomeNetwork5G"
      - "HomeNetwork2.4G"
    monitor_edids:
      - "a8f3e2d1c9b5a7f6e4d2c1b9a8f7e6d5"  # Main monitor
      - "b9e4f3d2c1a8b7e6f5d4c3b2a1e9f8d7"  # Secondary monitor

  - name: work
    wifi_networks:
      - "OfficeWiFi"
      - "OfficeWiFi-5G"
    monitor_edids:
      - "c1f4e5d6a7b8c9d1e2f3a4b5c6d7e8f9"  # Work monitor

  - name: library
    wifi_networks:
      - "LibraryPublic"
    # No monitor EDIDs - laptop only

  - name: cafe
    wifi_networks:
      - "CoffeeShopGuest"
      - "StarBucks WiFi"
EOF
```

**Important Notes:**
- WiFi networks are matched by ANY - if any network from the list is visible, location matches
- Monitor EDIDs are matched by ANY - if any monitor EDID matches, location matches
- Location matches if EITHER WiFi OR monitor criteria match
- Use descriptive location names (home, work, library, cafe, etc.)
- Locations are checked in order - first match wins

#### Step 3: Set Up SOPS Encryption

Location configurations must be encrypted with SOPS because WiFi network names can reveal your physical location.

**Generate Age Key (if not already done):**
```bash
# On the target machine, generate age key
nix run nixpkgs#age-keygen -- -o ~/.config/sops/age/keys.txt

# Get the public key
nix run nixpkgs#age-keygen -- -y ~/.config/sops/age/keys.txt
# Example output: age1abc123def456...
```

**Update .sops.yaml:**

Add your machine's age key to `.sops.yaml` in the repository root:

```yaml
keys:
  # ... existing keys ...
  - &server_ali-framework-laptop age1abc123def456...  # Your public key

creation_rules:
  # ... existing rules ...
  - path_regex: secrets/ali-framework-laptop/[^/]+\.(yaml|json|env|ini|bin)$
    key_groups:
    - age:
      - *admin_ali
      - *ali_personal
      - *server_ali-framework-laptop
```

**Encrypt and Store Location Config:**

```bash
# Copy to secrets directory
cp /tmp/locations-ali-desktop.yaml secrets/ali-desktop/locations.yaml

# Encrypt with SOPS
nix run nixpkgs#sops -- -e -i secrets/ali-desktop/locations.yaml

# Verify encryption (should show encrypted content)
cat secrets/ali-desktop/locations.yaml

# Clean up temporary file
rm /tmp/locations-ali-desktop.yaml
```

**Test Location Detection:**

After rebuilding your configuration:
```bash
# Test detection
detect-location

# Test with verbose output
detect-location --verbose

# Test with custom config path
detect-location --config ~/.config/location-detection/locations.yaml --verbose
```

### 2. Audio Context Configuration

The audio context module manages speaker and microphone volumes based on detected location.

#### Configuration File

The audio rules are configured in `home/machines/<hostname>/audio-context/default.nix`:

```nix
home.file.".config/audio-context/rules.yaml".text = ''
  # Default microphone volume when location is unknown or no rule matches
  default_mic_volume: 100

  # Exclude these audio sinks from automatic volume adjustment
  # (headphones, bluetooth devices, etc.)
  exclude_sink_patterns:
    - bluez.*              # Bluetooth devices
    - .*headphone.*        # Headphones
    - .*headset.*          # Headsets

  # Per-location volume rules
  rules:
    - location: home
      output_volume: 50    # Speaker volume (0-100)
      mic_volume: 75       # Microphone volume (0-100)

    - location: work
      output_volume: 40
      mic_volume: 85

    - location: library
      output_volume: 0     # Muted
      mic_volume: 0        # Muted

    - location: cafe
      output_volume: 20
      mic_volume: 0        # Muted for privacy
'';
```

#### Volume Behavior

**Known Locations:**
- Speakers: Set to configured `output_volume`
- Microphone: Set to configured `mic_volume`

**Unknown Locations:**
- Speakers: **Muted (0)** for safety
- Microphone: Set to `default_mic_volume` (default: 100)

**Excluded Devices:**
- Headphones and Bluetooth devices are NEVER adjusted
- Only built-in speakers/microphones are managed

#### Systemd Services

Three systemd services manage audio:

1. **User Service: `audio-context-boot`**
   - Runs on login/boot after PipeWire starts
   - Detects location and sets appropriate volumes

2. **System Service: `audio-context-pre-suspend`**
   - Runs before system suspend
   - Mutes speakers to prevent loud audio on resume

3. **System Service: `audio-context-resume`**
   - Runs after system resume
   - Waits 5 seconds for WiFi to reconnect
   - Detects location and sets appropriate volumes

#### Testing Audio Context

```bash
# Manually test volume script
audio-context-volume --location home --verbose

# Check service status
systemctl --user status audio-context-boot.service
systemctl status audio-context-pre-suspend.service
systemctl status audio-context-resume.service

# View service logs
journalctl --user -u audio-context-boot.service -f
journalctl -u audio-context-pre-suspend.service -f
journalctl -u audio-context-resume.service -f

# Manually trigger services
systemctl --user start audio-context-boot.service
```

### 3. EasyEffects Profiles

EasyEffects profiles allow you to configure per-machine audio processing pipelines.

#### Adding Profiles

1. **Create profiles in EasyEffects GUI:**
   - Open EasyEffects
   - Configure your audio effects (EQ, compressor, etc.)
   - Export preset as JSON

2. **Copy JSON to your machine directory:**
   ```bash
   cp ~/Downloads/MyProfile.json \
      ~/git/personal/nix-config/home/machines/ali-desktop/easyeffects/profiles/
   ```

3. **Rebuild configuration:**
   ```bash
   just switch
   ```

4. **Profiles are deployed to:**
   ```
   ~/.config/easyeffects/output/MyProfile.json
   ```

#### Profile Structure

All `.json` files in the `profiles/` directory are automatically deployed to `~/.config/easyeffects/output/`.

Example directory:
```
home/machines/ali-desktop/easyeffects/profiles/
├── .gitkeep
├── bass-boost.json
├── voice-clarity.json
└── headphone-eq.json
```

## Troubleshooting

### Location Detection Issues

**Location always shows "unknown":**
```bash
# Check what's being detected
detect-location --show-monitors --verbose
detect-location --show-wifi --verbose

# Verify config is decrypted
cat ~/.config/location-detection/locations.yaml

# Check SOPS deployment
ls -la ~/.config/location-detection/
```

**WiFi not detected:**
```bash
# Test NetworkManager
nmcli dev wifi list

# Check if NetworkManager is running
systemctl status NetworkManager.service
```

**Monitor EDIDs not matching:**
```bash
# Get current EDIDs
detect-location --show-monitors

# Check /sys directly
for edid in /sys/class/drm/card*/card*-*/edid; do
  echo "$edid: $(sha1sum < "$edid" 2>/dev/null | awk '{print $1}')"
done
```

### Audio Context Issues

**Volumes not changing:**
```bash
# Check if services are enabled
systemctl --user list-unit-files | grep audio-context
systemctl list-unit-files | grep audio-context

# Check service status
systemctl --user status audio-context-boot.service
systemctl status audio-context-pre-suspend.service

# Test manually
LOCATION=$(detect-location)
echo "Detected location: $LOCATION"
audio-context-volume --location "$LOCATION" --verbose
```

**PulseAudio/PipeWire connection errors:**
```bash
# Check PipeWire is running
systemctl --user status pipewire.service wireplumber.service

# Check environment variables
echo $XDG_RUNTIME_DIR
ls -la /run/user/$(id -u)/

# Test pamixer directly
pamixer --get-volume
pamixer --source --get-volume
```

**Suspend hooks not running:**
```bash
# Check system services
systemctl status audio-context-pre-suspend.service
systemctl status audio-context-resume.service

# View logs during suspend/resume cycle
journalctl -f -u audio-context-pre-suspend.service -u audio-context-resume.service

# Manually trigger suspend hook
sudo systemctl start audio-context-pre-suspend.service
```

### EasyEffects Issues

**Profiles not deploying:**
```bash
# Check if files exist in config
ls -la ~/.config/easyeffects/output/

# Verify source files
ls -la ~/git/personal/nix-config/home/machines/$(hostname)/easyeffects/profiles/

# Rebuild and check
just switch
```

## Advanced Configuration

### Custom Location Detection Config Path

You can override the default config path:

```bash
# Via environment variable
export LOCATION_CONFIG=/path/to/custom/locations.yaml
detect-location

# Via command line
detect-location --config /path/to/custom/locations.yaml
```

### Multiple Monitors at Different Locations

If you use the same monitor at multiple locations, you can combine WiFi and monitor criteria:

```yaml
locations:
  - name: home-desk
    wifi_networks:
      - "HomeNetwork5G"
    monitor_edids:
      - "abc123..."  # Main monitor (also at work)

  - name: work-desk
    wifi_networks:
      - "OfficeWiFi"
    monitor_edids:
      - "abc123..."  # Same main monitor
```

The combination of WiFi + monitor uniquely identifies the location.

### Debugging with Verbose Mode

For detailed debugging, use verbose mode on all tools:

```bash
# Location detection with full details
detect-location --verbose

# Audio context with full details
audio-context-volume --location home --verbose
```

## Security Considerations

1. **WiFi Network Privacy**: Never commit unencrypted `locations.yaml` - WiFi network combinations can pinpoint your physical location
2. **Age Key Security**: Keep your age private key (`~/.config/sops/age/keys.txt`) secure and backed up
3. **SOPS Encryption**: Always verify files are encrypted before committing:
   ```bash
   head secrets/ali-desktop/locations.yaml
   # Should show "sops:" and encrypted content, not plain text
   ```

## References

- Location Detection Script: `/home/ali/git/personal/nix-config/pkgs/detect-location/`
- Audio Context Script: `/home/ali/git/personal/nix-config/pkgs/audio-context-volume/`
- Suspend Services Module: `/home/ali/git/personal/nix-config/modules/audio-context-suspend.nix`
- SOPS Configuration: `/home/ali/git/personal/nix-config/.sops.yaml`
