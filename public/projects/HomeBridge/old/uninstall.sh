#!/bin/sh

# ==========================================
# OpenWrt Homebridge Uninstaller (Custom Build)
# ==========================================

echo -e "\n--- Homebridge Uninstaller By PeDitX ---\n"

echo ">>> [1/2] Removing Container..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^homebridge$"; then
    docker stop homebridge > /dev/null 2>&1
    docker rm homebridge > /dev/null 2>&1
    echo "   - Container removed."
else
    echo "   - Container not found."
fi

echo ">>> [2/2] Removing Firewall Rules..."
FOUND=0
# Clean all Homebridge related rules (UI, mDNS, etc.)
for rule in $(uci show firewall | grep "name='Allow_Homebridge'" | cut -d. -f2 | cut -d= -f1 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
    FOUND=1
done

if [ "$FOUND" -eq 1 ]; then
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rules removed."
else
    echo "   - Firewall rules not found."
fi

# Note: We do NOT revert the global 'forward=ACCEPT' rule automatically,
# because your Nextcloud and other Bridge containers rely on it.

echo -e "\nUninstallation Complete."
echo "Note: Configuration data in '/opt/homebridge' was NOT deleted."
echo "------------------------------------------"
