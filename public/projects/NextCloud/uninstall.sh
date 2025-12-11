#!/bin/sh

# ==========================================
# OpenWrt Nextcloud Uninstaller (Silent)
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

if uci get firewall.Allow_Nextcloud >/dev/null 2>&1; then
    uci delete firewall.Allow_Nextcloud > /dev/null 2>&1
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rule removed."
else
    echo "   - Firewall rule not found."
fi

echo -e "\nUninstallation Complete."
echo "Note: Your files in '/opt/nextcloud/data' were NOT deleted."
echo "------------------------------------------"
