#!/bin/sh

# ==========================================
# OpenWrt Music Assistant Installer
# Auto-Detects Drives & Adds UI Menu
# ==========================================

CONFIG_DIR="/opt/music_assistant/data"
MEDIA_BASE="/mnt"

echo -e "\n--- Music Assistant By PeDitX ---\n"

echo ">>> [1/6] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth
    modprobe veth
    service dockerd start
    sleep 5
fi

echo ">>> [2/6] Detecting Music Storage..."
FOUND_DRIVE=0
# Fix permissions on USB drives so Music Assistant can read them
for drive in $MEDIA_BASE/sd*; do
    if [ -d "$drive" ]; then
        echo "   - Found Drive: $drive"
        chmod 777 "$drive" 2>/dev/null
        FOUND_DRIVE=1
    fi
done
if [ $FOUND_DRIVE -eq 0 ]; then
    echo "   - No external drive yet (Add it later in settings)."
fi

echo ">>> [3/6] Configuring Firewall..."
# Music Assistant uses port 8095 for Web UI
# Since it runs in Host Mode, we open this port
for rule in $(uci show firewall | grep "name='Allow_MusicAssistant'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_MusicAssistant'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='8095'
uci set firewall.@rule[-1].target='ACCEPT'

# UDP range often used for discovery/streaming protocols
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_MusicAssistant_UDP'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='1900 5353'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured (Port 8095)."

echo ">>> [4/6] Preparing Directories..."
mkdir -p "$CONFIG_DIR"
chmod -R 777 "$CONFIG_DIR"

echo ">>> [5/6] Deploying Music Assistant..."
docker stop mass >/dev/null 2>&1
docker rm mass >/dev/null 2>&1

# Runs in Host Mode for DLNA/Cast discovery
docker run -d \
  --name mass \
  --restart=unless-stopped \
  --network host \
  -e TZ=Asia/Tehran \
  -v "$CONFIG_DIR":/data \
  -v "$MEDIA_BASE":/media \
  ghcr.io/music-assistant/server:stable > /dev/null 2>&1

echo ">>> [6/6] Creating PeDitXOS Menu..."
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_mass.lua
module("luci.controller.peditxos_mass", package.seeall)
function index()
    -- Rank 60 places it after Desktop (50)
    entry({"admin", "peditxos", "mass"}, template("peditxos/mass"), "Music Assistant", 60)
end
EOF

mkdir -p /usr/lib/lua/luci/view/peditxos
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/mass.htm
<%+header%>
<h2 name="content">Music Assistant by PeDitX</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="margin-bottom: 15px;">
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:8095" target="_blank" class="cbi-button cbi-button-apply">
                Open Full Screen
            </a>
            <p style="margin-top: 5px; color: #666;">
                <b>Music Location:</b> Browse to <code>/media</code> to find your USB drives.
            </p>
        </div>
        <div style="border: 1px solid #ccc;">
            <iframe 
                src="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:8095" 
                style="width: 100%; height: 800px; border: none;">
            </iframe>
        </div>
    </div>
</div>
<%+footer%>
EOF

rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo -e "\nSUCCESS! Music Assistant Installed."
echo "Access: http://$(uci get network.lan.ipaddr):8095"
echo "------------------------------------------"
