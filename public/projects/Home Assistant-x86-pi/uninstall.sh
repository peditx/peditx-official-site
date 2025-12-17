#!/bin/sh

# ==========================================
# OpenWrt Home Assistant Uninstaller
# Removes Container, Firewall & Menu
# ==========================================

echo -e "\n--- Home Assistant Uninstaller ---\n"

echo ">>> [1/3] Removing Container..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^homeassistant$"; then
    docker stop homeassistant > /dev/null 2>&1
    docker rm homeassistant > /dev/null 2>&1
    echo "   - Container removed."
else
    echo "   - Container not found."
fi

echo ">>> [2/3] Removing UI Menu..."
rm -f /usr/lib/lua/luci/controller/peditxos_ha.lua
rm -f /usr/lib/lua/luci/view/peditxos/ha.htm
rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache
echo "   - Menu removed."

echo ">>> [3/3] Removing Firewall Rules..."
FOUND=0
for rule in $(uci show firewall | grep "name='Allow_HomeAssistant'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
    FOUND=1
done

if [ "$FOUND" -eq 1 ]; then
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rule removed."
fi

echo -e "\nUninstallation Complete."
echo "Note: Config data in '/opt/homeassistant/config' was NOT deleted."
echo "------------------------------------------"
