#!/bin/sh

# ==========================================
# OpenWrt Nextcloud Installer (With Menu)
# Cloud Storage + Firewall Fix + PeDitXOS Menu
# ==========================================

DATA_DIR="/opt/nextcloud/data"

echo -e "\n--- Nextcloud By PeDitX ---\n"

echo ">>> [1/5] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth
    modprobe veth
    service dockerd start
    sleep 5
fi

echo ">>> [2/5] Configuring Firewall (Bridge Fix)..."
# 1. Clean old rules
for rule in $(uci show firewall | grep "name='Allow_Nextcloud'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# 2. Allow Port 8080
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Nextcloud'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='8080'
uci set firewall.@rule[-1].target='ACCEPT'

# 3. CRITICAL: Enable Forwarding for Docker Bridge
# Nextcloud needs this to communicate with the network
uci set firewall.@defaults[0].forward='ACCEPT'

uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [3/5] Preparing Data Directory..."
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
fi
# Fix permissions for www-data (uid 33)
chown -R 33:33 "$DATA_DIR"

echo ">>> [4/5] Deploying Nextcloud..."
docker stop nextcloud >/dev/null 2>&1
docker rm nextcloud >/dev/null 2>&1

docker run -d \
  --name nextcloud \
  --restart=unless-stopped \
  -p 8080:80 \
  -v "$DATA_DIR":/var/www/html \
  nextcloud:latest > /dev/null 2>&1

echo ">>> [5/5] Creating PeDitXOS Menu..."
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_nextcloud.lua
module("luci.controller.peditxos_nextcloud", package.seeall)
function index()
    -- Rank 20 places it after Home Assistant (10) but before Plex (30)
    entry({"admin", "peditxos", "nextcloud"}, template("peditxos/nextcloud"), "Nextcloud Storage", 20)
end
EOF

mkdir -p /usr/lib/lua/luci/view/peditxos
# Button-Only View to avoid iframe blocking issues
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/nextcloud.htm
<%+header%>
<h2 name="content">Nextcloud Personal Cloud</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="text-align: center; padding: 50px;">
            <p style="font-size: 16px; margin-bottom: 20px;">
                Access your files, photos, and documents securely.
            </p>
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:8080" target="_blank" class="cbi-button cbi-button-apply" style="font-size: 18px; padding: 10px 30px;">
                Open Nextcloud Dashboard
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

echo -e "\nSUCCESS! Nextcloud & Menu Installed."
echo "Access: http://$(uci get network.lan.ipaddr):8080"
echo "------------------------------------------"
