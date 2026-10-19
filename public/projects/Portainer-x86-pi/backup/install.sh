#!/bin/sh

# ==========================================
# OpenWrt Portainer Installer (With Menu)
# Management UI + Firewall + PeDitXOS Menu
# ==========================================

echo -e "\n--- Portainer By PeDitX ---\n"

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
for rule in $(uci show firewall | grep "name='Allow_Portainer'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# Allow Port 9000
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Portainer'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='9000'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [3/5] Cleaning old container..."
docker stop portainer >/dev/null 2>&1
docker rm portainer >/dev/null 2>&1

echo ">>> [4/5] Deploying Portainer..."
# Using Host Network mode for best compatibility on OpenWrt
docker run -d \
  --name portainer \
  --restart=always \
  --network=host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest > /dev/null 2>&1

echo ">>> [5/5] Creating PeDitXOS Menu..."
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_portainer.lua
module("luci.controller.peditxos_portainer", package.seeall)
function index()
    -- Rank 90 places it near the end (System Tools)
    entry({"admin", "peditxos", "portainer"}, template("peditxos/portainer"), "Portainer (Docker)", 90)
end
EOF

mkdir -p /usr/lib/lua/luci/view/peditxos
# Button-Only View because Portainer blocks Iframes
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/portainer.htm
<%+header%>
<h2 name="content">Portainer Management</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="text-align: center; padding: 50px;">
            <p style="font-size: 16px; margin-bottom: 20px;">
                Manage your containers via Portainer.
            </p>
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:9000" target="_blank" class="cbi-button cbi-button-apply" style="font-size: 18px; padding: 10px 30px;">
                Open Portainer Dashboard
            </a>
            <p style="margin-top: 20px; color: #888; font-size: 12px;">
                (Opened in new tab for security reasons)
            </p>
        </div>
    </div>
</div>
<%+footer%>
EOF

rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo -e "\nSUCCESS! Portainer & Menu Installed."
echo "Access: http://$(uci get network.lan.ipaddr):9000"
echo "------------------------------------------"
