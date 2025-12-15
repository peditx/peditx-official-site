#!/bin/sh

# ==========================================
# OpenWrt Homebridge Custom Installer (Store Safe)
# ==========================================

DATA_DIR="/opt/homebridge"
CONFIG_FILE="$DATA_DIR/config.json"

echo -e "\n--- Homebridge Custom Build (Store Safe) ---\n"

echo ">>> [1/5] Firewall Config..."
uci set firewall.@defaults[0].forward='ACCEPT'
for rule in $(uci show firewall | grep "name='Allow_Homebridge'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done
uci add firewall rule >/dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Homebridge_UI'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='8581'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
service firewall restart >/dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [2/5] Preparing Directories & Config..."
mkdir -p "$DATA_DIR"
chmod -R 777 "$DATA_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
cat <<EOF > "$CONFIG_FILE"
{
  "bridge": {
    "name": "Homebridge",
    "username": "CC:22:3D:E3:CE:30",
    "port": 51826,
    "pin": "031-45-154"
  },
  "platforms": [
    {
      "name": "Config",
      "port": 8581,
      "platform": "config"
    }
  ]
}
EOF
echo "   - Config file created."
fi

echo ">>> [3/5] Cleaning old container..."
docker stop homebridge >/dev/null 2>&1
docker rm homebridge >/dev/null 2>&1

echo ">>> [4/5] Deploying Homebridge (With Dependencies)..."

# Run container in background
docker run -d \
  --name homebridge \
  --restart=unless-stopped \
  -p 8581:8581 \
  -v "$DATA_DIR":/root/.homebridge \
  -e TZ=Asia/Tehran \
  -e HOMEBRIDGE_CONFIG_UI_SUDO=false \
  node:lts-alpine \
  /bin/sh -c "echo '>>> Installing System Dependencies...' && apk add --no-cache sudo git make g++ python3 && echo '>>> Installing Homebridge (NPM)...' && npm install -g --unsafe-perm homebridge homebridge-config-ui-x && echo '>>> Starting hb-service...' && hb-service run --allow-root --path /root/.homebridge" >/dev/null 2>&1

echo -e "\n------------------------------------------"
echo "INSTALLATION STARTED! (Safety Timeout: 600s)"
echo "------------------------------------------"

# SAFE LOG WATCHER LOOP
# Checks logs every 3 seconds. Exits on success OR timeout.
# This prevents infinite hanging.

MAX_RETRIES=200 # 200 * 3s = 600 seconds (10 mins) timeout
COUNT=0
LAST_LOG=""

while [ $COUNT -lt $MAX_RETRIES ]; do
    # 1. Check if container died
    if ! docker ps | grep -q homebridge; then
        echo "ERROR: Container stopped unexpectedly!"
        exit 1
    fi

    # 2. Get the last line of log
    CURRENT_LOG=$(docker logs --tail 1 homebridge 2>&1)

    # 3. Print if it's new
    if [ "$CURRENT_LOG" != "$LAST_LOG" ]; then
        echo "$CURRENT_LOG"
        LAST_LOG="$CURRENT_LOG"
    fi

    # 4. Check for Success Trigger
    # "Logging to" means hb-service started writing to file -> UI is ready
    if echo "$CURRENT_LOG" | grep -q "Logging to"; then
        break
    fi

    sleep 3
    COUNT=$((COUNT+1))
done

if [ $COUNT -ge $MAX_RETRIES ]; then
    echo "WARNING: Installation timed out waiting for success message."
    echo "It might still be running. Check manually."
else
    echo -e "\n------------------------------------------"
    echo "SUCCESS! Homebridge Web UI is Ready."
    echo "UI Access: http://$(uci get network.lan.ipaddr):8581"
    echo "User/Pass: admin / admin"
    echo "------------------------------------------"
fi
