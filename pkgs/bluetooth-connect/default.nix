{
  writeShellScriptBin,
  bluez,
  ...
}:
writeShellScriptBin "bluetooth-connect" ''
  #!/bin/bash

  # Check if MAC address argument is provided
  if [ -z "$1" ]; then
    echo "Usage: bluetooth-connect <MAC_ADDRESS>"
    exit 1
  fi

  MAC_ADDRESS="$1"

  # Check if Bluetooth is powered on
  if ${bluez}/bin/bluetoothctl show | grep -q "Powered: no"; then
    echo "Bluetooth is off, powering on..."
    echo "power on" | ${bluez}/bin/bluetoothctl
    # Wait for the adapter to be ready
    sleep 2
  fi

  # Connect to the device
  echo "Connecting to $MAC_ADDRESS..."
  echo "connect $MAC_ADDRESS" | ${bluez}/bin/bluetoothctl
''
