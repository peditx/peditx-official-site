#!/bin/sh

# ==========================================
# OpenWrt Linux Desktop Uninstaller
# Removes Container, Firewall Rules & Menu
# ==========================================

echo -e "\n--- Linux Desktop Uninstaller ---\n"

echo ">>> [1/3] Removing Container..."
# Stop and remove the container named 'desktop'
if docker ps -a --format '{{.Names}}' | grep -Eq "^desktop$"; then
    docker stop desktop > /dev/null 2>&1
    docker rm desktop > /dev/null 2>&1
    echo "   - Container removed."
else
    echo "   - Container not found."
fi

echo ">>> [2/3] Removing UI Menu..."
# Remove the controller and view files
rm -f /usr/lib/lua/luci/controller/peditxos_desktop.lua
rm -f /usr/lib/lua/luci/view/peditxos/desktop.htm

# Also clean up any potential leftovers from previous attempts
rm -f /usr/lib/lua/luci/controller/peditxos_webtop.lua
rm -f /usr/lib/lua/luci/view/peditxos/webtop.htm
rm -f /usr/lib/lua/luci/controller/peditxos_alpine.lua
rm -f /usr/lib/lua/luci/view/peditxos/alpine.htm

# Clear LuCI cache
rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache
echo "   - Menu removed."

echo ">>> [3/3] Removing Firewall Rules..."
FOUND=0
# Remove rule named 'Allow_Desktop' or 'Allow_Webtop'
for rule in $(uci show firewall | grep -E "name='Allow_(Desktop|Webtop)'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
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
echo "Refresh your browser."
echo "------------------------------------------"
