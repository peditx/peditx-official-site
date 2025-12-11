#!/bin/sh

# ==========================================
# OpenWrt Portainer Uninstaller (Silent)
# ==========================================

echo -e "\n--- Portainer By PeDitX ---\n"

echo ">>> [1/2] Removing Container..."

# Check and remove container silent
if docker ps -a --format '{{.Names}}' | grep -Eq "^portainer$"; then
    docker stop portainer > /dev/null 2>&1
    docker rm portainer > /dev/null 2>&1
    echo "   - Portainer container removed."
else
    echo "   - Container not found."
fi

echo ">>> [2/2] Removing Firewall Rules..."

# Delete rule silent
if uci get firewall.Allow_Portainer >/dev/null 2>&1; then
    uci delete firewall.Allow_Portainer > /dev/null 2>&1
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rule removed."
else
    echo "   - Firewall rule not found."
fi

echo -e "\nUninstallation Complete."
echo "------------------------------------------"
