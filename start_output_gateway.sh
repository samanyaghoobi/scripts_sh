#!/bin/bash

# Configuration
REMOTE_OUTPUT_HOST=""
VPN_CONFIG="/etc/openfortivpn.conf"
# List of ports to forward (Tensor of "port:proto")
PORTS=("14121:tcp" "14122:tcp" "14123:tcp" "14124:tcp" "14124:udp" "14125:tcp" "2195:tcp")

# Check dependencies
command -v openfortivpn >/dev/null 2>&1 || { echo >&2 "openfortivpn is required!"; exit 1; }
command -v socat >/dev/null 2>&1 || { echo >&2 "socat is required! Install with: sudo apt install socat"; exit 1; }

# Function to start VPN
start_vpn() {
    echo "[+] Connecting to VPN..."
    sudo openfortivpn --config "$VPN_CONFIG"
}

# Function to start forwarding for a single port
start_forward_port() {
    local port=$1 proto=$2
    echo "[+] Forwarding ${proto^^} port $port -> $REMOTE_OUTPUT_HOST:$port"
    while true; do
        if [ "$proto" = "tcp" ]; then
            socat TCP4-LISTEN:$port,fork,reuseaddr TCP4:$REMOTE_OUTPUT_HOST:$port
        else
            socat UDP4-LISTEN:$port,fork,reuseaddr UDP4:$REMOTE_OUTPUT_HOST:$port
        fi
        echo "[!] Forward on $port/$proto failed -- retrying in 3s..."
        sleep 3
    done
}

# Main loop: keep VPN and forwarding alive
while true; do
    echo "[*] Starting VPN + forwarders at $(date)"
    start_vpn &
    VPN_PID=$!

    # Launch forwarding for each port
    FORWARD_PIDS=()
    for entry in "${PORTS[@]}"; do
        port="${entry%%:*}"
        proto="${entry##*:}"
        start_forward_port "$port" "$proto" &
        FORWARD_PIDS+=("$!")
    done

    # Wait for VPN to disconnect
    wait $VPN_PID
    echo "[!] VPN disconnected - killing forwarders..."
    for pid in "${FORWARD_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done

    echo "[*] Will retry in 5 seconds..."
    sleep 5
done
