#!/usr/bin/env bash

set -euo pipefail

# Constants
# SHA1 hash of empty input (unchanging value)
readonly EMPTY_SHA1="da39a3ee5e6b4b0d3255bfef95601890afd80709"

# Configuration
CONFIG_FILE=""
SHOW_MONITORS=false
SHOW_WIFI=false
VERBOSE=false

# Logging helper
log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[detect-location] $*" >&2
    fi
}

# Show usage
usage() {
    cat <<EOF
Usage: detect-location [OPTIONS]

Detect current location based on WiFi networks and monitor EDIDs.

OPTIONS:
    --config <path>      Path to locations.yaml config file
    --show-monitors      Display current monitor EDID hashes and exit
    --show-wifi          Display visible WiFi networks and exit
    --verbose            Show detailed matching information
    -h, --help           Show this help message

CONFIGURATION:
    Config file priority:
    1. --config argument
    2. LOCATION_CONFIG environment variable
    3. Default: ~/.config/location-detection/locations.yaml

OUTPUT:
    Prints detected location name (e.g., "home", "work") or "unknown"

EXAMPLES:
    detect-location
    detect-location --config /path/to/locations.yaml
    detect-location --show-monitors
    detect-location --show-wifi --verbose
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --show-monitors)
                SHOW_MONITORS=true
                shift
                ;;
            --show-wifi)
                SHOW_WIFI=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done
}

# Get WiFi networks (all visible SSIDs, not just connected)
get_wifi_networks() {
    local networks=()

    log "Scanning for visible WiFi networks..."

    # Use nmcli to list all visible WiFi networks
    # Format: SSID (one per line)
    while IFS= read -r ssid; do
        # Skip empty lines and header
        if [[ -n "$ssid" && "$ssid" != "SSID" ]]; then
            networks+=("$ssid")
            log "Found WiFi network: $ssid"
        fi
    done < <(nmcli -t -f SSID dev wifi list 2>/dev/null | sort -u)

    printf '%s\n' "${networks[@]}"
}

# Get monitor EDID hashes (streaming approach)
get_monitor_edids() {
    local edid_hashes=()

    log "Reading monitor EDIDs from /sys/class/drm..."
    log "Empty EDID hash reference: $EMPTY_SHA1"

    # Iterate through all EDID files in /sys/class/drm
    for edid_file in /sys/class/drm/card*/card*-*/edid; do
        if [[ -f "$edid_file" && -r "$edid_file" ]]; then
            log "Processing EDID file: $edid_file"

            # Stream EDID directly to sha1sum (no memory buffering)
            local hash
            hash=$(sha1sum < "$edid_file" 2>/dev/null | awk '{print $1}')

            # Check if hash is valid and not empty EDID
            if [[ -n "$hash" && "$hash" != "$EMPTY_SHA1" ]]; then
                edid_hashes+=("$hash")
                log "Found monitor EDID hash: $hash (from $edid_file)"
            else
                log "Skipping empty or unset EDID: $edid_file"
            fi
        fi
    done

    printf '%s\n' "${edid_hashes[@]}"
}

# Show current monitors and exit
show_monitors() {
    echo "Current Monitor EDID Hashes:"
    echo "============================"

    local hashes
    mapfile -t hashes < <(get_monitor_edids)

    if [[ ${#hashes[@]} -eq 0 ]]; then
        echo "No monitors detected"
        exit 0
    fi

    for hash in "${hashes[@]}"; do
        echo "  $hash"
    done

    exit 0
}

# Show current WiFi networks and exit
show_wifi() {
    echo "Visible WiFi Networks:"
    echo "======================"

    local networks
    mapfile -t networks < <(get_wifi_networks)

    if [[ ${#networks[@]} -eq 0 ]]; then
        echo "No WiFi networks detected"
        exit 0
    fi

    for network in "${networks[@]}"; do
        echo "  $network"
    done

    exit 0
}

# Determine config file path
get_config_path() {
    # Priority: CLI arg > env var > default
    if [[ -n "$CONFIG_FILE" ]]; then
        echo "$CONFIG_FILE"
    elif [[ -n "${LOCATION_CONFIG:-}" ]]; then
        echo "$LOCATION_CONFIG"
    else
        echo "$HOME/.config/location-detection/locations.yaml"
    fi
}

# Parse YAML config and detect location
detect_location() {
    local config_path
    config_path=$(get_config_path)

    log "Using config file: $config_path"

    if [[ ! -f "$config_path" ]]; then
        log "Config file not found: $config_path"
        echo "unknown"
        return 0
    fi

    # Get current WiFi networks and monitor EDIDs
    local wifi_networks
    mapfile -t wifi_networks < <(get_wifi_networks)

    local monitor_edids
    mapfile -t monitor_edids < <(get_monitor_edids)

    log "Detected ${#wifi_networks[@]} WiFi network(s)"
    log "Detected ${#monitor_edids[@]} monitor(s)"

    # Get number of locations in config
    local location_count
    location_count=$(yq '.config.locations | length' "$config_path" 2>/dev/null || yq '.locations | length' "$config_path")

    log "Found $location_count location(s) in config"

    # Iterate through locations
    for ((i = 0; i < location_count; i++)); do
        local location_name
        location_name=$(yq ".config.locations[$i].name // .locations[$i].name" "$config_path")

        log "Checking location: $location_name"

        # Check WiFi networks
        local wifi_match=false
        local wifi_network_count
        wifi_network_count=$(yq ".config.locations[$i].wifi_networks // .locations[$i].wifi_networks | length" "$config_path" 2>/dev/null || echo "0")

        if [[ "$wifi_network_count" != "0" && "$wifi_network_count" != "null" ]]; then
            for ((j = 0; j < wifi_network_count; j++)); do
                local config_ssid
                config_ssid=$(yq ".config.locations[$i].wifi_networks[$j] // .locations[$i].wifi_networks[$j]" "$config_path")

                # Check if this SSID is in our detected networks
                for detected_ssid in "${wifi_networks[@]}"; do
                    if [[ "$detected_ssid" == "$config_ssid" ]]; then
                        log "WiFi match found: $config_ssid"
                        wifi_match=true
                        break 2
                    fi
                done
            done
        fi

        # Check monitor EDIDs
        local monitor_match=false
        local monitor_edid_count
        monitor_edid_count=$(yq ".config.locations[$i].monitor_edids // .locations[$i].monitor_edids | length" "$config_path" 2>/dev/null || echo "0")

        if [[ "$monitor_edid_count" != "0" && "$monitor_edid_count" != "null" ]]; then
            for ((k = 0; k < monitor_edid_count; k++)); do
                local config_edid
                config_edid=$(yq ".config.locations[$i].monitor_edids[$k] // .locations[$i].monitor_edids[$k]" "$config_path")

                # Check if this EDID is in our detected monitors
                for detected_edid in "${monitor_edids[@]}"; do
                    if [[ "$detected_edid" == "$config_edid" ]]; then
                        log "Monitor EDID match found: $config_edid"
                        monitor_match=true
                        break 2
                    fi
                done
            done
        fi

        # Location matches if WiFi OR monitor matches
        if [[ "$wifi_match" == "true" || "$monitor_match" == "true" ]]; then
            log "Location matched: $location_name"
            echo "$location_name"
            return 0
        fi
    done

    log "No location matched"
    echo "unknown"
}

# Main
main() {
    parse_args "$@"

    # Handle display-only modes
    if [[ "$SHOW_MONITORS" == "true" ]]; then
        show_monitors
    fi

    if [[ "$SHOW_WIFI" == "true" ]]; then
        show_wifi
    fi

    # Detect and print location
    detect_location
}

main "$@"
