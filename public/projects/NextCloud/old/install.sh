#!/bin/sh

# ==========================================
# OpenWrt Nextcloud Installer (Final Stable)
# ==========================================

DATA_DIR="/opt/nextcloud/data"

echo -e "\n--- Nextcloud By PeDitX ---\n"

echo ">>> [1/5] Checking Docker installation..."

# Install Docker dependencies if missing
if ! command -v docker >/dev/null 2>&1; then
    echo "   - Installing Docker & dependencies..."
    opkg update > /dev/null 2>&1
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth > /dev/null 2>&1
    modprobe veth > /dev/null 2>&1
    service dockerd enable > /dev/null 2>&1
    service dockerd start > /dev/null 2>&1
    sleep 5
fi

# Ensure Docker service is running
if ! docker info >/dev/null 2>&1; then
    service dockerd start > /dev/null 2>&1
    sleep 5
fi

echo ">>> [2/5] Configuring Firewall..."

# 1. Clean old firewall rules to prevent duplicates
for rule in $(uci show firewall | grep "name='Allow_Nextcloud'" | cut -d. -f2 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# 2. Add Firewall Rule for Port 8080
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Nextcloud'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='8080'
uci set firewall.@rule[-1].target='ACCEPT'

# 3. GLOBAL FORWARDING FIX (The Solution)
# Allows traffic to flow between LAN and Docker Bridge networks
uci set firewall.@defaults[0].forward='ACCEPT'

# Apply Firewall Changes
uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured (Port 8080 & Global Forwarding)."

echo ">>> [3/5] Permissions & Data..."
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
    echo "   - Created data directory."
fi
# Set ownership to www-data (uid 33)
chown -R 33:33 "$DATA_DIR"

echo ">>> [4/5] Cleaning old containers..."
docker stop nextcloud >/dev/null 2>&1
docker rm nextcloud >/dev/null 2>&1

echo ">>> [5/5] Deploying Nextcloud Container..."

# Pull image first to ensure we have it (optional but good practice)
# docker pull nextcloud:latest

docker run -d \
  --name nextcloud \
  --restart=unless-stopped \
  -p 8080:80 \
  -v "$DATA_DIR":/var/www/html \
  nextcloud:latest > /dev/null 2>&1

echo -e "\nSUCCESS! Nextcloud is running."
echo "Access: http://$(uci get network.lan.ipaddr):8080"
echo "Note: Wait 2-3 minutes for the database to initialize."
echo "------------------------------------------"
