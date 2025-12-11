#!/bin/sh

# ==========================================
# OpenWrt Nextcloud Uninstaller (Robust)
# ==========================================

echo -e "\n--- Nextcloud By PeDitX ---\n"

echo ">>> [1/2] Removing Container..."

if docker ps -a --format '{{.Names}}' | grep -Eq "^nextcloud$"; then
    docker stop nextcloud > /dev/null 2>&1
    docker rm nextcloud > /dev/null 2>&1
    echo "   - Nextcloud container removed."
else
    echo "   - Container not found."
fi

echo ">>> [2/2] Removing Firewall Rules..."

# Smart remove: Find the exact rule ID and delete it
FOUND=0
for rule in $(uci show firewall | grep "name='Allow_Nextcloud'" | cut -d. -f2 | sort -u); do
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

# Note: We do NOT revert LAN forwarding automatically as it might break other containers.

echo -e "\nUninstallation Complete."
echo "Note: Your files in '/opt/nextcloud/data' were NOT deleted."
echo "------------------------------------------"
