#!/bin/sh

# ==========================================
# OpenWrt Nextcloud Uninstaller
# Removes Container, Firewall & Menu
# ==========================================

echo -e "\n--- Nextcloud Uninstaller ---\n"

echo ">>> [1/3] Removing Container..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^nextcloud$"; then
    docker stop nextcloud > /dev/null 2>&1
    docker rm nextcloud > /dev/null 2>&1
    echo "   - Container removed."
else
    echo "   - Container not found."
fi

echo ">>> [2/3] Removing UI Menu..."
rm -f /usr/lib/lua/luci/controller/peditxos_nextcloud.lua
rm -f /usr/lib/lua/luci/view/peditxos/nextcloud.htm
rm -rf /tmp/luci-modulecache/
rm -f /tmp/luci-indexcache
echo "   - Menu removed."

echo ">>> [3/3] Removing Firewall Rules..."
FOUND=0
for rule in $(uci show firewall | grep "name='Allow_Nextcloud'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
    FOUND=1
done

if [ "$FOUND" -eq 1 ]; then
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rule removed."
fi

# Note: We do NOT revert global forwarding (lan forward=ACCEPT) automatically
# because other containers might depend on it.

echo -e "\nUninstallation Complete."
echo "Note: Your files in '/opt/nextcloud/data' were NOT deleted."
echo "------------------------------------------"
