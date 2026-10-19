#!/bin/sh

# ==========================================
# OpenWrt Node-RED Installer (With Menu)
# Automation Tool + Firewall + PeDitXOS Menu
# ==========================================

DATA_DIR="/opt/nodered/data"

echo -e "\n--- Node-RED By PeDitX ---\n"

echo ">>> [1/5] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth
    modprobe veth
    service dockerd start
    sleep 5
fi

echo ">>> [2/5] Configuring Firewall..."
# Clean old rules
for rule in $(uci show firewall | grep "name='Allow_NodeRED'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# Allow Port 1880
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
# Node-RED runs as user 1000 (node-red)
chown -R 1000:1000 "$DATA_DIR" 2>/dev/null || chmod -R 777 "$DATA_DIR"

echo ">>> [4/5] Deploying Node-RED..."
docker stop nodered >/dev/null 2>&1
docker rm nodered >/dev/null 2>&1

docker run -d \
  --name nodered \
  --restart=unless-stopped \
  -e TZ=Asia/Tehran \
  -p 1880:1880 \
  -v "$DATA_DIR":/data \
  nodered/node-red:latest > /dev/null 2>&1

echo ">>> [5/5] Creating PeDitXOS Menu..."
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_nodered.lua
module("luci.controller.peditxos_nodered", package.seeall)
function index()
    -- Rank 15 places it right after Home Assistant (10)
    entry({"admin", "peditxos", "nodered"}, template("peditxos/nodered"), "Node-RED Flow", 15)
end
EOF

mkdir -p /usr/lib/lua/luci/view/peditxos
# Button-Only View
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/nodered.htm
<%+header%>
<h2 name="content">Node-RED Automation</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="text-align: center; padding: 50px;">
            <p style="font-size: 16px; margin-bottom: 20px;">
                Low-code programming for event-driven applications.
            </p>
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:1880" target="_blank" class="cbi-button cbi-button-apply" style="font-size: 18px; padding: 10px 30px;">
                Open Node-RED Editor
            </a>
            <p style="margin-top: 20px; color: #888; font-size: 12px;">
                (Opened in new tab for full canvas experience)
            </p>
        </div>
    </div>
</div>
<%+footer%>
EOF

rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo -e "\nSUCCESS! Node-RED & Menu Installed."
echo "Access: http://$(uci get network.lan.ipaddr):1880"
echo "------------------------------------------"
