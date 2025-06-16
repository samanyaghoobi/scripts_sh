#!/bin/bash

REMOTE_IP=""
REMOTE_USER=""
LOCAL_PORT=""

# SSH command to establish SOCKS5 proxy
create_tunnel() {
    echo "Creating SOCKS5 tunnel..."
    ssh -N -D 0.0.0.0:$LOCAL_PORT $REMOTE_USER@$REMOTE_IP -o ServerAliveInterval=60 -o ExitOnForwardFailure=yes
}

# Infinite loop to keep the tunnel open
while true; do
    create_tunnel
    echo "Connection lost, reconnecting..."
    sleep 5
done

