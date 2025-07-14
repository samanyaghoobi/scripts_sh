#!/bin/bash

REMOTE_IP=""
REMOTE_USER=""
LOCAL_PORT="7891"
LOGDIR="$HOME/logs"
LOGFILE="$LOGDIR/ssh_tunnel_GR.log"

# ساخت پوشه لاگ اگر وجود نداشت
if [ ! -d "$LOGDIR" ]; then
    mkdir -p "$LOGDIR"
fi

# ساخت فایل لاگ اگر وجود نداشت
if [ ! -f "$LOGFILE" ]; then
    touch "$LOGFILE"
fi

create_tunnel() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Creating SOCKS5 tunnel on 0.0.0.0:$LOCAL_PORT ..." | tee -a "$LOGFILE"
    ssh -N -D 0.0.0.0:$LOCAL_PORT $REMOTE_USER@$REMOTE_IP \
        -o ServerAliveInterval=60 \
        -o ExitOnForwardFailure=yes \
        -o TCPKeepAlive=yes \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        2>&1 | tee -a "$LOGFILE"
}

while true; do
    create_tunnel
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Connection lost, reconnecting..." | tee -a "$LOGFILE"
    sleep 1
done
