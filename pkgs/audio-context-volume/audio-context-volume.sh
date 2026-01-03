#!/usr/bin/env bash

set -euo pipefail

# Configuration
CONFIG_FILE="$HOME/.config/audio-context/rules.yaml"
LOCATION=""
VERBOSE=false

# Logging helper
log() {
    echo "[audio-context-volume] $*" >&2
}

# Verbose logging
verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "$*"
    fi
}

# Show usage
usage() {
    cat <<EOF
Usage: audio-context-volume --location <location> [OPTIONS]

Apply context-aware volume settings based on provided location.

REQUIRED:
    --location <name>    Current location name (e.g., "home", "work", "unknown")

OPTIONS:
    --config <path>      Path to rules.yaml config file
                         (default: ~/.config/audio-context/rules.yaml)
    --verbose            Show detailed information
    -h, --help           Show this help message

CONFIGURATION:
    Reads volume rules from YAML configuration file.
    Location should be provided by a wrapper script that calls detect-location.

BEHAVIOR:
    - Speakers: Apply location-specific volume (or mute if unknown)
    - Microphone: Apply location-specific volume (or default 100 if unknown)
    - Headphones: Never adjusted (excluded via patterns)

EXAMPLES:
    audio-context-volume --location home
    audio-context-volume --location unknown --verbose
    audio-context-volume --location work --config /path/to/rules.yaml
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
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

    # Validate required arguments
    if [[ -z "$LOCATION" ]]; then
        echo "Error: --location is required" >&2
        usage
        exit 1
    fi
}

# Get current audio sink (output device)
get_current_sink() {
    # Get default sink using wpctl (parse all sinks between "Sinks:" and "Sources:" sections)
    local sink_id
    sink_id=$(wpctl status | awk '/^ ├─ Sinks:/,/^ ├─ Sources:/' | grep '\*' | awk '{print $3}' | tr -d '*.' || echo "")

    if [[ -z "$sink_id" ]]; then
        verbose_log "No default sink found"
        return 1
    fi

    # Get sink name/description
    local sink_name
    sink_name=$(wpctl inspect "$sink_id" | grep "node.name" | cut -d'"' -f2 || echo "")

    verbose_log "Current sink ID: $sink_id"
    verbose_log "Current sink name: $sink_name"

    echo "$sink_name"
}

# Check if sink matches excluded patterns (headphones, bluetooth, etc.)
is_sink_excluded() {
    local sink_name="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    # Get number of exclude patterns
    local pattern_count
    pattern_count=$(yq '.exclude_sink_patterns | length' "$CONFIG_FILE" 2>/dev/null || echo "0")

    if [[ "$pattern_count" == "0" || "$pattern_count" == "null" ]]; then
        return 1
    fi

    # Check each pattern
    for ((i = 0; i < pattern_count; i++)); do
        local pattern
        pattern=$(yq ".exclude_sink_patterns[$i]" "$CONFIG_FILE")

        # Use grep for pattern matching
        if echo "$sink_name" | grep -qE "$pattern"; then
            verbose_log "Sink '$sink_name' matches excluded pattern: $pattern"
            return 0
        fi
    done

    return 1
}

# Get default microphone volume from config
get_default_mic_volume() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "100"
        return 0
    fi

    local default_vol
    default_vol=$(yq '.default_mic_volume' "$CONFIG_FILE" 2>/dev/null || echo "100")

    if [[ "$default_vol" == "null" ]]; then
        echo "100"
    else
        echo "$default_vol"
    fi
}

# Find matching rule for location
find_rule_for_location() {
    local location="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    # Get number of rules
    local rule_count
    rule_count=$(yq '.rules | length' "$CONFIG_FILE" 2>/dev/null || echo "0")

    if [[ "$rule_count" == "0" || "$rule_count" == "null" ]]; then
        return 1
    fi

    # Find matching rule
    for ((i = 0; i < rule_count; i++)); do
        local rule_location
        rule_location=$(yq ".rules[$i].location" "$CONFIG_FILE")

        if [[ "$rule_location" == "$location" ]]; then
            echo "$i"
            return 0
        fi
    done

    return 1
}

# Apply volume settings
apply_volumes() {
    local location="$1"

    verbose_log "Applying volumes for location: $location"

    # Get current sink
    local current_sink
    if ! current_sink=$(get_current_sink); then
        log "Warning: Could not detect current audio sink"
        return 1
    fi

    verbose_log "Detected current audio sink: $current_sink"

    # Check if sink is excluded (headphones, bluetooth, etc.)
    local sink_excluded=false
    if is_sink_excluded "$current_sink"; then
        log "Current sink detected: $current_sink"
        log "Skipping volume adjustment (sink matches excluded pattern - likely headphones or bluetooth device)"
        sink_excluded=true
    fi

    # Handle unknown location
    if [[ "$location" == "unknown" ]]; then
        log "Unknown location - applying safe defaults"

        # Mute speakers for safety (but not headphones)
        if [[ "$sink_excluded" == "false" ]]; then
            verbose_log "Muting speakers (volume = 0)"
            pamixer --set-volume 0
            log "Speakers muted (unknown location)"
        fi

        # Set microphone to default volume (100 unless configured)
        local default_mic_volume
        default_mic_volume=$(get_default_mic_volume)
        verbose_log "Setting microphone to default volume: $default_mic_volume"
        pamixer --default-source --set-volume "$default_mic_volume"
        log "Microphone set to default volume: $default_mic_volume"

        return 0
    fi

    # Find rule for this location
    local rule_index
    if ! rule_index=$(find_rule_for_location "$location"); then
        log "Warning: No rule found for location '$location', using safe defaults"

        # Same as unknown location
        if [[ "$sink_excluded" == "false" ]]; then
            pamixer --set-volume 0
            log "Speakers muted (no rule for location)"
        fi

        local default_mic_volume
        default_mic_volume=$(get_default_mic_volume)
        pamixer --default-source --set-volume "$default_mic_volume"
        log "Microphone set to default volume: $default_mic_volume"

        return 0
    fi

    verbose_log "Found rule at index: $rule_index"

    # Get volumes from rule
    local output_volume
    output_volume=$(yq ".rules[$rule_index].output_volume" "$CONFIG_FILE" 2>/dev/null || echo "null")

    local mic_volume
    mic_volume=$(yq ".rules[$rule_index].mic_volume" "$CONFIG_FILE" 2>/dev/null || echo "null")

    # Apply output volume (speakers only, not headphones)
    if [[ "$output_volume" != "null" && "$sink_excluded" == "false" ]]; then
        verbose_log "Setting speaker volume to: $output_volume"
        pamixer --set-volume "$output_volume"
        log "Speaker volume set to: $output_volume (location: $location)"
    elif [[ "$sink_excluded" == "true" ]]; then
        verbose_log "Skipping speaker volume (excluded sink)"
    fi

    # Apply microphone volume
    if [[ "$mic_volume" != "null" ]]; then
        verbose_log "Setting microphone volume to: $mic_volume"
        pamixer --default-source --set-volume "$mic_volume"
        log "Microphone volume set to: $mic_volume (location: $location)"
    fi
}

# Main
main() {
    parse_args "$@"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "Warning: Config file not found: $CONFIG_FILE"
        log "Skipping volume adjustment"
        exit 0
    fi

    verbose_log "Using config file: $CONFIG_FILE"

    # Apply volume settings based on provided location
    apply_volumes "$LOCATION"
}

main "$@"
