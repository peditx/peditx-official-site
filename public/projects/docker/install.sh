#!/bin/sh

# ==========================================
# OpenWrt Docker Installer (Silent)
# ==========================================

echo -e "\n--- Docker By PeDitX ---\n"

echo ">>> [1/3] Updating Package Lists..."
# Update silent
opkg update > /dev/null 2>&1
echo "   - Update complete."

echo ">>> [2/3] Installing Docker & Dependencies..."

# Check if docker is already installed
if command -v docker >/dev/null 2>&1; then
    echo "   - Docker is already installed."
else
    # Install Docker, Compose, LuCI app, and veth kernel module
    # kmod-veth is crucial for network bridges
    echo "   - Installing packages (This may take a moment)..."
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth > /dev/null 2>&1
    
    # Load veth module immediately
    modprobe veth > /dev/null 2>&1
    echo "   - Packages installed."
fi

echo ">>> [3/3] Starting Services..."

# Enable and start Docker service
service dockerd enable > /dev/null 2>&1
service dockerd start > /dev/null 2>&1

# Wait for initialization
echo "   - Waiting for daemon to initialize..."
sleep 5

# Verification
if docker info >/dev/null 2>&1; then
    echo -e "\nSUCCESS! Docker is installed and running."
    echo "Version: $(docker -v)"
else
    echo -e "\nWARNING: Docker installed but service is not responding."
    echo "Try rebooting your device."
fi
echo "------------------------------------------"
