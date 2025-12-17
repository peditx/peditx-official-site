#!/bin/sh

# ==========================================
# OpenWrt Home Assistant Installer (Silent)
# ==========================================

CONFIG_DIR="/opt/homeassistant/config"

echo -e "\n--- Home Assistant By PeDitX ---\n"

echo ">>> [1/4] Checking Docker installation..."

# Check if docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "   - Installing Docker & dependencies (Silent)..."
    opkg update > /dev/null 2>&1
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth > /dev/null 2>&1
    modprobe veth > /dev/null 2>&1
    service dockerd enable > /dev/null 2>&1
    service dockerd start > /dev/null 2>&1
    echo "   - Waiting for Docker..."
    sleep 5
else
    echo "   - Docker is ready."
fi

if ! docker info >/dev/null 2>&1; then
    service dockerd start > /dev/null 2>&1
    sleep 5
fi

echo ">>> [2/4] Configuring Firewall..."

uci delete firewall.Allow_HomeAssistant >/dev/null 2>&1
uci commit firewall > /dev/null 2>&1

uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_HomeAssistant'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='8123'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall > /dev/null 2>&1

service firewall restart > /dev/null 2>&1
echo "   - Firewall rule added for port 8123."

echo ">>> [3/4] Checking Config Directory..."

if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    echo "   - Created: $CONFIG_DIR"
else
    echo "   - Found existing config."
fi

echo ">>> [4/4] Deploying Home Assistant..."

docker stop homeassistant >/dev/null 2>&1
docker rm homeassistant >/dev/null 2>&1

docker run -d \
  --name homeassistant \
  --privileged \
  --restart=unless-stopped \
  -e TZ=Asia/Tehran \
  -v "$CONFIG_DIR":/config \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable > /dev/null 2>&1

echo -e "\nSUCCESS! Home Assistant is running."
echo "Access: http://$(uci get network.lan.ipaddr):8123"
echo "Note: First boot takes a few minutes."
echo "------------------------------------------"
