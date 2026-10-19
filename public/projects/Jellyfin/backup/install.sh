#!/bin/sh

# ==========================================
# OpenWrt Jellyfin Installer (Auto-Detect + HW Accel)
# ==========================================

CONFIG_DIR="/opt/jellyfin/config"
CACHE_DIR="/opt/jellyfin/cache"
# We map /mnt to /media so Jellyfin sees ALL drives automatically
MEDIA_BASE="/mnt"

echo -e "\n--- Jellyfin Server By PeDitX ---\n"

echo ">>> [1/6] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth
    modprobe veth
    service dockerd start
    sleep 5
fi

echo ">>> [2/6] Detecting Storage..."
FOUND_DRIVE=0
for drive in $MEDIA_BASE/sd*; do
    if [ -d "$drive" ]; then
        echo "   - Found Drive: $drive"
        chmod 777 "$drive" 2>/dev/null
        FOUND_DRIVE=1
    fi
done
if [ $FOUND_DRIVE -eq 0 ]; then
    echo "   - No external drive yet (Jellyfin will see it later)."
fi

echo ">>> [3/6] Configuring Firewall..."
# Clean old rules
for rule in $(uci show firewall | grep "name='Allow_Jellyfin'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

# Rule 1: Web UI (TCP 8096)
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Jellyfin_Web'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='8096'
uci set firewall.@rule[-1].target='ACCEPT'

# Rule 2: DLNA/Discovery (UDP 1900, 7359)
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Jellyfin_DLNA'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port='1900 7359'
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

echo ">>> [5/6] Preparing Directories..."
mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
chmod -R 777 "$CONFIG_DIR" "$CACHE_DIR"

echo ">>> [6/6] Deploying Jellyfin..."
docker stop jellyfin >/dev/null 2>&1
docker rm jellyfin >/dev/null 2>&1

docker run -d \
  --name jellyfin \
  --restart=unless-stopped \
  --network host \
  -e TZ=Asia/Tehran \
  $DEVICE_FLAGS \
  -v "$CONFIG_DIR":/config \
  -v "$CACHE_DIR":/cache \
  -v "$MEDIA_BASE":/media \
  jellyfin/jellyfin:latest > /dev/null 2>&1

echo ">>> Creating PeDitXOS Menu..."
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_jellyfin.lua
module("luci.controller.peditxos_jellyfin", package.seeall)
function index()
    -- Rank 35 places it after Plex (30)
    entry({"admin", "peditxos", "jellyfin"}, template("peditxos/jellyfin"), "Jellyfin Media", 35)
end
EOF

mkdir -p /usr/lib/lua/luci/view/peditxos
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/jellyfin.htm
<%+header%>
<h2 name="content">Jellyfin Server</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="margin-bottom: 15px;">
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:8096" target="_blank" class="cbi-button cbi-button-apply">
                Open Jellyfin Web UI
            </a>
            <p style="margin-top: 5px; color: #666;">
                <b>Add Library:</b> Browse to <code>/media</code> folder to find your drives.
            </p>
        </div>
        <div style="border: 1px solid #ccc;">
            <iframe 
                src="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:8096" 
                style="width: 100%; height: 800px; border: none;">
            </iframe>
        </div>
    </div>
</div>
<%+footer%>
EOF

rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo -e "\nSUCCESS! Jellyfin & Menu Installed."
echo "Access: http://$(uci get network.lan.ipaddr):8096"
echo "------------------------------------------"
