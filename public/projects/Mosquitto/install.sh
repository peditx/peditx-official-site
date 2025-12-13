#!/bin/sh

# ==========================================
# OpenWrt Mosquitto (MQTT) Installer
# ==========================================

BASE_DIR="/opt/mosquitto"
CONF_DIR="$BASE_DIR/config"
DATA_DIR="$BASE_DIR/data"
LOG_DIR="$BASE_DIR/log"

echo -e "\n--- Mosquitto By PeDitX ---\n"

echo ">>> [1/5] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update >/dev/null 2>&1
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth >/dev/null 2>&1
    modprobe veth >/dev/null 2>&1
    service dockerd start >/dev/null 2>&1
    sleep 5
fi

echo ">>> [2/5] Configuring Firewall (Port 1883)..."
# Remove old rule
for rule in $(uci show firewall | grep "name='Allow_Mosquitto'" | cut -d. -f2 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# Add new rule
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Mosquitto'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='1883'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [3/5] Preparing Config & Directories..."
mkdir -p "$CONF_DIR" "$DATA_DIR" "$LOG_DIR"

# Create default configuration file (Essential for v2.0+)
# We enable anonymous access for easier local usage
cat <<EOF > "$CONF_DIR/mosquitto.conf"
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
listener 1883
allow_anonymous true
EOF

# Fix permissions (User 1883 inside container needs access)
chown -R 1883:1883 "$BASE_DIR" 2>/dev/null || chmod -R 777 "$BASE_DIR"

echo "   - Config file created."

echo ">>> [4/5] Cleaning old container..."
docker stop mosquitto >/dev/null 2>&1
docker rm mosquitto >/dev/null 2>&1

echo ">>> [5/5] Deploying Mosquitto..."
docker run -d \
  --name mosquitto \
  --restart=unless-stopped \
  -p 1883:1883 \
  -p 9001:9001 \
  -v "$CONF_DIR":/mosquitto/config \
  -v "$DATA_DIR":/mosquitto/data \
  -v "$LOG_DIR":/mosquitto/log \
  eclipse-mosquitto:latest > /dev/null 2>&1

echo -e "\nSUCCESS! MQTT Broker is running."
echo "Address: $(uci get network.lan.ipaddr)"
echo "Port:    1883"
echo "------------------------------------------"
