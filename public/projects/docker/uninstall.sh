#!/bin/sh

# ==========================================
# OpenWrt Docker Uninstaller (Silent)
# ==========================================

echo -e "\n--- Docker By PeDitX ---\n"

echo ">>> [1/3] Stopping Services..."

# Stop all running containers first (to prevent orphans)
if command -v docker >/dev/null 2>&1; then
    echo "   - Stopping all running containers..."
    docker stop $(docker ps -q) > /dev/null 2>&1
fi

# Stop Docker service
service dockerd stop > /dev/null 2>&1
service dockerd disable > /dev/null 2>&1
echo "   - Docker service stopped."

echo ">>> [2/3] Removing Packages..."

# Remove packages silent
# We use --force-removal-of-dependent-packages just in case
echo "   - Removing Docker, Compose, and LuCI app..."
opkg remove dockerd docker-compose luci-app-dockerman kmod-veth --force-removal-of-dependent-packages > /dev/null 2>&1

echo "   - Packages removed."

echo ">>> [3/3] Cleaning up..."

# Optional: Remove network interfaces created by docker
ip link delete docker0 > /dev/null 2>&1

echo -e "\nUninstallation Complete."
echo "Note: Docker data volumes (in /opt or /mnt) were NOT deleted to save your data."
echo "------------------------------------------"
