#!/bin/sh

# ==========================================
# OpenWrt Plex Uninstaller
# ==========================================

echo -e "\n--- Plex Uninstaller ---\n"

echo ">>> [1/2] Removing Container..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^plex$"; then
    docker stop plex > /dev/null 2>&1
    docker rm plex > /dev/null 2>&1
    echo "   - Container removed."
else
    echo "   - Container not found."
fi

echo ">>> [2/2] Removing Firewall Rules..."
FOUND=0
for rule in $(uci show firewall | grep "name='Allow_Plex'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
    FOUND=1
done

if [ "$FOUND" -eq 1 ]; then
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rules removed."
fi

echo -e "\nUninstallation Complete."
echo "Note: Your library data in '/opt/plex' was NOT deleted."
echo "------------------------------------------"
