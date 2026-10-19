#!/bin/sh

# ==========================================
# OpenWrt Netdata Installer (Native + UI Menu)
# All-in-One: Installs Package & Adds UI Menu
# ==========================================

echo -e "\n--- Netdata Native By PeDitX ---\n"

echo ">>> [1/5] Installing Netdata Package..."
opkg update >/dev/null 2>&1
if opkg install netdata >/dev/null 2>&1; then
    echo "   - Package installed."
else
    echo "   - Retrying installation..."
    opkg install netdata
fi

echo ">>> [2/5] Configuring Access..."
CONF_FILE="/etc/netdata/netdata.conf"
if [ -f "$CONF_FILE" ]; then
    cp "$CONF_FILE" "$CONF_FILE.bak"
    # Enable external access (bind to 0.0.0.0)
    sed -i 's/bind to = 127.0.0.1/bind to = 0.0.0.0/g' "$CONF_FILE"
    sed -i 's/bind socket to IP = 127.0.0.1/bind socket to IP = 0.0.0.0/g' "$CONF_FILE"
    echo "   - Remote access enabled."
fi

echo ">>> [3/5] Configuring Firewall..."
for rule in $(uci show firewall | grep "name='Allow_Netdata'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
done
uci add firewall rule > /dev/null 2>&1
uci set firewall.@rule[-1].name='Allow_Netdata'
uci set firewall.@rule[-1].src='lan'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].dest_port='19999'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall > /dev/null 2>&1
service firewall restart > /dev/null 2>&1
echo "   - Firewall configured."

echo ">>> [4/5] Starting Service..."
service netdata enable >/dev/null 2>&1
service netdata restart >/dev/null 2>&1

echo ">>> [5/5] Creating PeDitXOS Menu..."

# Create Controller (Safe Mode - Appends to menu)
mkdir -p /usr/lib/lua/luci/controller
cat << 'EOF' > /usr/lib/lua/luci/controller/peditxos_netdata.lua
module("luci.controller.peditxos_netdata", package.seeall)
function index()
    entry({"admin", "peditxos", "netdata"}, template("peditxos/netdata"), "NetData", 99)
end
EOF

# Create View (Iframe)
mkdir -p /usr/lib/lua/luci/view/peditxos
cat << 'EOF' > /usr/lib/lua/luci/view/peditxos/netdata.htm
<%+header%>
<h2 name="content">NetData Monitoring by PeDitX</h2>
<div class="cbi-map">
    <div class="cbi-section">
        <div style="margin-bottom: 15px;">
            <a href="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:19999" target="_blank" class="cbi-button cbi-button-apply">
                Open Full Window
            </a>
        </div>
        <div style="border: 1px solid #ccc;">
            <iframe 
                src="http://<%=luci.sys.exec("uci get network.lan.ipaddr"):gsub("\n", "")%>:19999" 
                style="width: 100%; height: 800px; border: none;">
            </iframe>
        </div>
    </div>
</div>
<%+footer%>
EOF

# Clear Cache
rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache

echo -e "\nSUCCESS! Netdata & Menu Installed."
echo "Check the new 'PeDitXOS' tab in your router settings."
echo "------------------------------------------"
