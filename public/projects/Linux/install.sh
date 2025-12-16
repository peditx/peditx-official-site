#!/bin/sh

# ==========================================
# OpenWrt Linux Desktop Installer (Stable)
# LXDE/Openbox + Essential Apps + Fixed Repos
# ==========================================

CONFIG_DIR="/opt/desktop/data"

echo -e "\n--- Linux Desktop By PeDitX ---\n"

echo ">>> [1/6] Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    opkg update
    opkg install dockerd docker-compose luci-app-dockerman kmod-veth
    modprobe veth
    service dockerd start
    sleep 5
fi

echo ">>> [2/6] Configuring Firewall..."
for rule in $(uci show firewall | grep "name='Allow_Desktop'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done

uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Desktop'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='3000'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1

echo ">>> [3/6] Preparing Directories..."
mkdir -p "$CONFIG_DIR"
chmod -R 777 "$CONFIG_DIR"

echo ">>> [4/6] Deploying Base Desktop..."
docker stop desktop >/dev/null 2>&1
docker rm desktop >/dev/null 2>&1

# Deploy stable alpine desktop
docker run -d \
  --name=desktop \
  --restart=unless-stopped \
  -p 3000:6901 \
  -v "$CONFIG_DIR":/home/alpine \
  -e TZ=Asia/Tehran \
  -e VNC_PASSWORD=password \
  --shm-size="1gb" \
  soff/tiny-remote-desktop:latest > /dev/null 2>&1

echo ">>> [5/6] Fixing Repos & Installing Apps..."
echo "   - Waiting for container to initialize..."
sleep 10

# FIX REPOS: We explicitly set community repos to ensure 'nano' and 'chromium' are found
docker exec desktop sh -c 'echo "http://dl-cdn.alpinelinux.org/alpine/latest-stable/main" > /etc/apk/repositories'
docker exec desktop sh -c 'echo "http://dl-cdn.alpinelinux.org/alpine/latest-stable/community" >> /etc/apk/repositories'

# Update and Install
echo "   - Installing Nano, Chromium, PCManFM..."
if docker exec desktop apk update > /dev/null 2>&1; then
    docker exec desktop apk add nano pcmanfm lxterminal chromium adwaita-icon-theme > /dev/null 2>&1
    echo "   - Apps installed successfully."
else
    echo "   - WARNING: Repo update failed. Check internet connection."
fi

# Create Desktop Shortcut for Chromium
docker exec desktop mkdir -p /home/alpine/Desktop > /dev/null 2>&1
docker exec desktop sh -c 'echo "[Desktop Entry]
Type=Application
Name=Chromium Browser
Exec=/usr/bin/chromium --no-sandbox
Icon=web-browser" > /home/alpine/Desktop/chromium.desktop' > /dev/null 2>&1
docker exec desktop chmod +x /home/alpine/Desktop/chromium.desktop > /dev/null 2>&1

echo ">>> [6/6] Creating PeDitXOS Menu..."
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_desktop.lua
module("luci.controller.peditxos_desktop", package.seeall)
function index()
    -- Renamed to "Linux Desktop" as requested
    entry({"admin", "peditxos", "desktop"}, template("peditxos/desktop"), "Linux Desktop", 50)
end
EOF

mkdir -p /usr/lib/lua/luci/view/peditxos
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/desktop.htm
<%+header%>
<h2 name="content">Linux Desktop by PeDitX</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="margin-bottom: 15px;">
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:3000" target="_blank" class="cbi-button cbi-button-apply">
                Open Full Screen
            </a>
            <p style="margin-top: 5px; color: #666;">
                <b>Apps Installed:</b> Nano, Chromium, File Manager<br>
                <b>Default User:</b> alpine | <b>Password:</b> password<br>
                <b>Right Click</b> on desktop to see menu.
            </p>
        </div>
        <div style="border: 1px solid #ccc;">
            <iframe 
                src="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:3000" 
                style="width: 100%; height: 800px; border: none;">
            </iframe>
        </div>
    </div>
</div>
<%+footer%>
EOF

rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo -e "\nSUCCESS! Linux Desktop Installed."
echo "Access: http://$(uci get network.lan.ipaddr):3000"
echo "------------------------------------------"
