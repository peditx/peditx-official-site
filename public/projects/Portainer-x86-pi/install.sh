#!/bin/sh

# ==========================================
# OpenWrt Portainer Installer (Silent Mode)
# ==========================================

echo -e "\n--- Portainer By PeDitX ---\n"

echo ">>> [1/3] Checking Docker installation..."

# Check if docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "   - Docker not found. Installing dependencies (Silent)..."
    
    # Update package lists silent
    opkg update > /dev/null 2>&1
    
    # Install Docker, Compose, and veth silent
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth > /dev/null 2>&1
    
    # Load veth module
    modprobe veth > /dev/null 2>&1
    
    # Enable and start Docker service silent
    service dockerd enable > /dev/null 2>&1
    service dockerd start > /dev/null 2>&1
    
    echo "   - Waiting for Docker initialization..."
    sleep 5
else
    echo "   - Docker is already installed."
fi

# Ensure Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "   - Starting Docker service..."
    service dockerd start > /dev/null 2>&1
    sleep 5
fi

echo ">>> [2/3] Configuring Firewall..."

# Remove old rule silent
uci delete firewall.Allow_Portainer >/dev/null 2>&1
uci commit firewall > /dev/null 2>&1

# Add Firewall Rule silent
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Portainer'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='9000'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall > /dev/null 2>&1

# Restart firewall silent
service firewall restart > /dev/null 2>&1
echo "   - Firewall rule added for port 9000."

echo ">>> [3/3] Deploying Portainer Container..."

# Stop and remove existing container silent
docker stop portainer >/dev/null 2>&1
docker rm portainer >/dev/null 2>&1

# Run Portainer in Host Mode silent
docker run -d \
  --name portainer \
  --restart=always \
  --network=host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest > /dev/null 2>&1

echo -e "\nSUCCESS! Portainer is running."
echo "Access: http://$(uci get network.lan.ipaddr):9000"
echo "------------------------------------------"
