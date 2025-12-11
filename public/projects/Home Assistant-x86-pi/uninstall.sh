#!/bin/sh

# ==========================================
# OpenWrt HA Uninstaller (Silent)
# ==========================================

echo -e "\n--- Home Assistant By PeDitX ---\n"

echo ">>> [1/2] Removing Container..."

if docker ps -a --format '{{.Names}}' | grep -Eq "^homeassistant$"; then
    docker stop homeassistant > /dev/null 2>&1
    docker rm homeassistant > /dev/null 2>&1
    echo "   - Home Assistant removed."
else
    echo "   - Container not found."
fi

echo ">>> [2/2] Removing Firewall Rules..."

if uci get firewall.Allow_HomeAssistant >/dev/null 2>&1; then
    uci delete firewall.Allow_HomeAssistant > /dev/null 2>&1
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rule removed."
else
    echo "   - Firewall rule not found."
fi

echo -e "\nUninstallation Complete."
echo "------------------------------------------"
