#!/bin/sh

# ==========================================
# OpenWrt Netdata Uninstaller (Native + UI)
# Removes Package, Firewall Rules & UI Menu
# ==========================================

echo -e "\n--- Netdata Native Uninstaller ---\n"

echo ">>> [1/3] Removing Netdata Package..."
# Stop and disable service
service netdata stop >/dev/null 2>&1
service netdata disable >/dev/null 2>&1

# Remove package and config directory
opkg remove netdata >/dev/null 2>&1
rm -rf /etc/netdata >/dev/null 2>&1
echo "   - Package removed."

echo ">>> [2/3] Removing UI Menu..."
# Remove the controller and view files we created
rm -f /usr/lib/lua/luci/controller/peditxos_netdata.lua
rm -f /usr/lib/lua/luci/view/peditxos/netdata.htm

# Remove the directory if it's empty
rmdir /usr/lib/lua/luci/view/peditxos 2>/dev/null

# Clear LuCI cache so the menu disappears immediately
rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache
echo "   - Menu removed."

echo ">>> [3/3] Removing Firewall Rules..."
FOUND=0
# Find and remove the specific rule
for rule in $(uci show firewall | grep "name='Allow_Netdata'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
    FOUND=1
done

if [ "$FOUND" -eq 1 ]; then
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rule removed."
else
    echo "   - Firewall rule not found."
fi

echo -e "\nUninstallation Complete."
echo "Refresh your browser to see the menu gone."
echo "------------------------------------------"
