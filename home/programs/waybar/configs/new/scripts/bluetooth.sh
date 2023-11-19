#!/usr/bin/env bash

# Identify current status of bluetooth
status=$(bluetoothctl show | grep "Powered" | awk '{print $2}')

toggle_bluetooth() {
	if [[ $status == "yes" ]]; then
		bluetoothctl power off
		echo "Bluetooth disable."
	else
		bluetoothctl power on
		echo "Bluetooth enable."
	fi
}

toggle_bluetooth
