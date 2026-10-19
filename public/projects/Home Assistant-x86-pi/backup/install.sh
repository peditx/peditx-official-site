#!/bin/sh

# ==========================================
# OpenWrt Home Assistant Installer (Clean Menu)
# Auto-Start + Firewall + Button-Only Menu
# ==========================================

CONFIG_DIR="/opt/homeassistant/config"

echo -e "\n--- Home Assistant By PeDitX ---\n"

echo ">>> [1/5] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth
    modprobe veth
    service dockerd start
    sleep 5
fi

echo ">>> [2/5] Configuring Firewall..."
for rule in $(uci show firewall | grep "name='Allow_HomeAssistant'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_HomeAssistant'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='8123'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [3/5] Preparing Directories..."
mkdir -p "$CONFIG_DIR"
chmod -R 777 "$CONFIG_DIR"

echo ">>> [4/5] Deploying Home Assistant..."
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

echo ">>> [5/5] Creating PeDitXOS Menu..."
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_ha.lua
module("luci.controller.peditxos_ha", package.seeall)
function index()
    entry({"admin", "peditxos", "ha"}, template("peditxos/ha"), "Home Assistant", 10)
end
EOF

mkdir -p /usr/lib/lua/luci/view/peditxos
# Updated View: Removes broken Iframe, keeps stylish button
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/ha.htm
<%+header%>
<h2 name="content">Home Assistant by PeDitX</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="text-align: center; padding: 50px;">
            <p style="font-size: 16px; margin-bottom: 20px;">
                Home Assistant is running safely in the background.
            </p>
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:8123" target="_blank" class="cbi-button cbi-button-apply" style="font-size: 18px; padding: 10px 30px;">
                Open Dashboard (Full Screen)
            </a>
            <p style="margin-top: 20px; color: #888; font-size: 12px;">
                (Embedded view is disabled due to HA security policies)
            </p>
        </div>
    </div>
</div>
<%+footer%>
EOF

rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo -e "\nSUCCESS! Home Assistant Installed."
echo "Access: http://$(uci get network.lan.ipaddr):8123"
echo "------------------------------------------"
