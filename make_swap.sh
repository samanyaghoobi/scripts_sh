#!/bin/bash

# Swap File Creation Script for Ubuntu 24.04
# Usage: ./create_swap.sh [size_in_gb]

# Function to display help
help() {
    echo "Usage: $0 [size_in_gb]"
    echo "Example: $0 4"
    echo "This script creates a swap file of the specified size in gigabytes."
    echo "- Ensure you have sufficient disk space before running the script."
    echo "- The created swap file will be permanent and enabled at boot."
}

# Check if help is needed
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    help
    exit 0
fi

# Check if a size is provided
if [[ -z "$1" ]]; then
    echo "Error: No size provided."
    help
    exit 1
fi

# Validate the size input
if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: Size must be a positive integer."
    help
    exit 1
fi

SWAP_SIZE="$1G"
SWAP_FILE="/swapfile"

# Create the swap file
echo "Creating swap file of size $SWAP_SIZE..."
sudo fallocate -l $SWAP_SIZE $SWAP_FILE

# Set the correct permissions
sudo chmod 600 $SWAP_FILE

# Set up the swap space
sudo mkswap $SWAP_FILE

# Activate the swap file
sudo swapon $SWAP_FILE

# Add the swap file to fstab for persistence
echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab

# Confirm the swap file is enabled
echo "Swap file created and enabled. Current swap status:"
sudo swapon --show
