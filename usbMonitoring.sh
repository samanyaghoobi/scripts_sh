#!/bin/bash

INFO_DIR="./usb_info"
mkdir -p "$INFO_DIR"

echo "Monitoring USB devices by port... Press Ctrl+C to stop."

udevadm monitor --udev --subsystem-match=usb | while read -r line; do
    if echo "$line" | grep -qE "add|remove"; then
        read -r dev_line
        devpath=$(echo "$dev_line" | grep -oP "(?<=/devices/).*")
        port=$(basename "$devpath")

        # Skip sub-interfaces like 1-10:1.0
        if [[ "$port" == *:* ]]; then
            continue
        fi

        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        file="$INFO_DIR/usb-$port.info"

        if echo "$line" | grep -q "add"; then
            # Delay to allow udev to populate device info
            sleep 0.5

            # Use udevadm info to get device details
            full_info=$(udevadm info --query=property --path="/devices/$devpath")

            model=$(echo "$full_info" | grep '^ID_MODEL=' | cut -d '=' -f2)
            vendor=$(echo "$full_info" | grep '^ID_VENDOR=' | cut -d '=' -f2)
            serial=$(echo "$full_info" | grep '^ID_SERIAL_SHORT=' | cut -d '=' -f2)
            vid=$(echo "$full_info" | grep '^ID_VENDOR_ID=' | cut -d '=' -f2)
            pid=$(echo "$full_info" | grep '^ID_MODEL_ID=' | cut -d '=' -f2)

            # Only log if full device info exists
            if [[ -n "$model" && -n "$vendor" ]]; then
                echo ""
                echo "[USB CONNECTED] $timestamp"
                echo "Port: $port"
                echo "Vendor: $vendor"
                echo "Model: $model"
                echo "ID: ${vid}:${pid}"
                echo "Serial: $serial"

                {
                    echo "Timestamp: $timestamp"
                    echo "Port: $port"
                    echo "Vendor: $vendor"
                    echo "Model: $model"
                    echo "ID: ${vid}:${pid}"
                    echo "Serial: $serial"
                } > "$file"
            fi

        elif echo "$line" | grep -q "remove"; then
            echo ""
            echo "[USB REMOVED] $timestamp"
            echo "Port: $port"

            if [[ -f "$file" ]]; then
                echo "Device info from file:"
                cat "$file"
                rm "$file"
            else
                echo "No device info found for this port."
            fi
        fi
    fi
done
