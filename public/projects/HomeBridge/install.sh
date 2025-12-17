#!/bin/sh

# ==========================================
# OpenWrt Homebridge Installer (With Menu)
# Apple HomeKit Gateway + Firewall Fix + Menu
# ==========================================

DATA_DIR="/opt/homebridge"

echo -e "\n--- Homebridge By PeDitX ---\n"

echo ">>> [1/5] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth
    modprobe veth
    service dockerd start
    sleep 5
fi

echo ">>> [2/5] Configuring Firewall..."
# 1. Clean old rules
for rule in $(uci show firewall | grep "name='Allow_Homebridge'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# 2. Add specific rule for UI
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Homebridge_UI'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='8581'
uci set firewall.@rule[-1].target='ACCEPT'

# 3. Allow mDNS (Apple Discovery)
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Homebridge_mDNS'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='5353'
uci set firewall.@rule[-1].target='ACCEPT'

# 4. Allow HomeKit Bridge Port
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Homebridge_Bridge'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='51000-52000 51826'
uci set firewall.@rule[-1].target='ACCEPT'

# 5. Ensure LAN Input is open (Required for Host Mode services)
LAN_ID=""
for section in $(uci show firewall | grep "=zone" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    name=$(uci -q get firewall.$section.name)
    if [ "$name" == "lan" ]; then
        LAN_ID="$section"
        break
    fi
done
if [ -n "$LAN_ID" ]; then
    uci set firewall.$LAN_ID.input='ACCEPT'
else
    uci set firewall.@defaults[0].input='ACCEPT'
fi

uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [3/5] Preparing Directories..."
mkdir -p "$DATA_DIR"
chmod -R 777 "$DATA_DIR"

echo ">>> [4/5] Cleaning old container..."
docker stop homebridge >/dev/null 2>&1
docker rm homebridge >/dev/null 2>&1

echo ">>> [5/5] Deploying Homebridge..."
docker run -d \
  --name homebridge \
  --restart=unless-stopped \
  --network host \
  -e TZ=Asia/Tehran \
  -e HOMEBRIDGE_CONFIG_UI=1 \
  -e HOMEBRIDGE_CONFIG_UI_PORT=8581 \
  -v "$DATA_DIR":/homebridge \
  homebridge/homebridge:latest > /dev/null 2>&1

echo ">>> [6/6] Creating PeDitXOS Menu..."
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_homebridge.lua
module("luci.controller.peditxos_homebridge", package.seeall)
function index()
    -- Rank 40: After Plex (30)
    entry({"admin", "peditxos", "homebridge"}, template("peditxos/homebridge"), "Homebridge (Apple)", 40)
end
EOF

mkdir -p /usr/lib/lua/luci/view/peditxos
# Button-Only View to avoid iframe blocking issues
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/homebridge.htm
<%+header%>
<h2 name="content">Homebridge Gateway</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="text-align: center; padding: 50px;">
            <p style="font-size: 16px; margin-bottom: 20px;">
                Connect non-Apple devices to HomeKit.
            </p>
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:8581" target="_blank" class="cbi-button cbi-button-apply" style="font-size: 18px; padding: 10px 30px;">
                Open Homebridge UI
            </a>
            <p style="margin-top: 20px; color: #888; font-size: 12px;">
                (Opened in new tab due to security policies)
            </p>
        </div>
    </div>
</div>
<%+footer%>
EOF

rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo -e "\nSUCCESS! Homebridge & Menu Installed."
echo "Access: http://$(uci get network.lan.ipaddr):8581"
echo "------------------------------------------"
