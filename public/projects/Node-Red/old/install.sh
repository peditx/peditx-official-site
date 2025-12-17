#!/bin/sh

# ==========================================
# OpenWrt Node-RED Installer
# ==========================================

DATA_DIR="/opt/nodered/data"

echo -e "\n--- Node-RED By PeDitX ---\n"

echo ">>> [1/5] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update >/dev/null 2>&1
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth >/dev/null 2>&1
    modprobe veth >/dev/null 2>&1
    service dockerd start >/dev/null 2>&1
    sleep 5
fi

echo ">>> [2/5] Configuring Firewall (Port 1880)..."
# Remove old rule
for rule in $(uci show firewall | grep "name='Allow_NodeRED'" | cut -d. -f2 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# Add new rule
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_NodeRED'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='1880'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [3/5] Preparing Directories..."
mkdir -p "$DATA_DIR"

# Node-RED runs as user 1000 inside container. 
# We must set permission to ensure it can write to the data folder.
chown -R 1000:1000 "$DATA_DIR" 2>/dev/null || chmod -R 777 "$DATA_DIR"
echo "   - Permissions set."

echo ">>> [4/5] Cleaning old container..."
docker stop nodered >/dev/null 2>&1
docker rm nodered >/dev/null 2>&1

echo ">>> [5/5] Deploying Node-RED..."
docker run -d \
  --name nodered \
  --restart=unless-stopped \
  -e TZ=Asia/Tehran \
  -p 1880:1880 \
  -v "$DATA_DIR":/data \
  nodered/node-red:latest > /dev/null 2>&1

echo -e "\nSUCCESS! Node-RED is running."
echo "Access: http://$(uci get network.lan.ipaddr):1880"
echo "Note: It might take a minute to start fully."
echo "------------------------------------------"
