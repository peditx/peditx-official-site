#!/bin/sh

# ==========================================
# OpenWrt Plex Installer (Fully Automated)
# Auto-detects Drives & GPU
# ==========================================

CONFIG_DIR="/opt/plex/config"
# We map /mnt to /data so Plex can see ALL connected USB drives automatically
MEDIA_BASE="/mnt"

echo -e "\n--- Plex Server By PeDitX ---\n"

echo ">>> [1/6] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update >/dev/null 2>&1
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth >/dev/null 2>&1
    modprobe veth >/dev/null 2>&1
    service dockerd start >/dev/null 2>&1
    sleep 5
fi

echo ">>> [2/6] Detecting Storage Devices..."
# Loop through mounted drives in /mnt to fix permissions automatically
FOUND_DRIVE=0
for drive in $MEDIA_BASE/sd*; do
    if [ -d "$drive" ]; then
        echo "   - Found Drive: $drive"
        # Fix permissions so Plex can read NTFS/Ext4 drives
        chmod 777 "$drive" 2>/dev/null
        FOUND_DRIVE=1
    fi
done

if [ $FOUND_DRIVE -eq 0 ]; then
    echo "   - No external USB drive detected yet (Safe to continue)."
    echo "     (Plex will see it automatically when you plug it in later)."
else
    echo "   - Permissions fixed for detected drives."
fi

echo ">>> [3/6] Configuring Firewall..."
# Clean old rules
for rule in $(uci show firewall | grep "name='Allow_Plex'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# Rule 1: Plex Web (TCP 32400)
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Plex_Web'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='32400'
uci set firewall.@rule[-1].target='ACCEPT'

# Rule 2: DLNA (UDP 1900)
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Plex_DLNA_UDP'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='1900'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [4/6] Checking Hardware Transcoding..."
DEVICE_FLAGS=""
if [ -d "/dev/dri" ]; then
    echo "   - Intel GPU detected! Enabling HW Transcoding."
    DEVICE_FLAGS="--device /dev/dri:/dev/dri"
    chmod 777 /dev/dri/renderD128 2>/dev/null
else
    echo "   - No GPU detected. Using CPU."
fi

echo ">>> [5/6] Preparing Config..."
mkdir -p "$CONFIG_DIR"
chmod -R 777 "$CONFIG_DIR"

echo ">>> [6/6] Deploying Plex..."
docker stop plex >/dev/null 2>&1
docker rm plex >/dev/null 2>&1

docker run -d \
  --name plex \
  --restart=unless-stopped \
  --network host \
  -e TZ=Asia/Tehran \
  -e PLEX_UID=0 \
  -e PLEX_GID=0 \
  -e VERSION=docker \
  $DEVICE_FLAGS \
  -v "$CONFIG_DIR":/config \
  -v "$MEDIA_BASE":/data \
  plexinc/pms-docker:latest > /dev/null 2>&1

echo -e "\nSUCCESS! Plex is running."
echo "Access: http://$(uci get network.lan.ipaddr):32400/web"
echo "Note: When adding libraries, browse to folder '/data' to see your USB drives."
echo "------------------------------------------"
