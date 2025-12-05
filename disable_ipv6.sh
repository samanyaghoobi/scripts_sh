#!/bin/bash

# Disable IPv6 permanently

# Modify sysctl.conf
echo "Disabling IPv6..."
{
    echo "net.ipv6.conf.all.disable_ipv6 = 1"
    echo "net.ipv6.conf.default.disable_ipv6 = 1"
    echo "net.ipv6.conf.lo.disable_ipv6 = 1"
} | sudo tee -a /etc/sysctl.conf

# Apply changes
sudo sysctl -p

# Verify if IPv6 is disabled
echo "IPv6 status:"
ip a | grep inet6

echo "IPv6 has been disabled permanently."
