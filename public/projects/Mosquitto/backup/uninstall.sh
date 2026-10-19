#!/bin/sh

# ==========================================
# OpenWrt Mosquitto Uninstaller
# ==========================================

echo -e "\n--- Mosquitto By PeDitX ---\n"

echo ">>> [1/2] Removing Container..."
if docker ps -a --format '{{.Names}}' | grep -Eq "^mosquitto$"; then
    docker stop mosquitto > /dev/null 2>&1
    docker rm mosquitto > /dev/null 2>&1
    echo "   - Container removed."
fi

echo ">>> [2/2] Removing Firewall Rules..."
FOUND=0
for rule in $(uci show firewall | grep "name='Allow_Mosquitto'" | cut -d. -f2 | sort -u); do
    uci delete firewall.$rule >/dev/null 2>&1
    FOUND=1
done

if [ "$FOUND" -eq 1 ]; then
    uci commit firewall > /dev/null 2>&1
    service firewall restart > /dev/null 2>&1
    echo "   - Firewall rule removed."
fi

echo -e "\nUninstallation Complete."
echo "Note: Data in '/opt/mosquitto' was NOT deleted."
echo "------------------------------------------"
