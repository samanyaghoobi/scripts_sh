#!/bin/bash

USB_ID="ID_SERIAL=00005719032121095710"

while true; do
    if lsusb | grep -q "$USB_ID"; then
        echo "USB وصل است"
    else
        echo "USB قطع شد - قفل کردن سیستم"
        loginctl lock-session
    fi
    sleep 2
done
