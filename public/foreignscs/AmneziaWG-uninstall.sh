#!/bin/sh

echo "Starting AmneziaWG uninstallation..."

# 1. Remove network interface and peer configuration
echo "Removing network configuration..."
uci -q delete network.awg1
uci -q delete network.amneziawg_awg1
uci commit network

# 2. Remove firewall zone and forwarding rules
echo "Removing firewall rules..."
# Find and delete the firewall zone by name
ZONE_SECTION_NAME=""
for s in $(uci show firewall | grep "=zone" | cut -d"." -f2); do
    if [ "$(uci -q get firewall.$s.name)" = "awg1" ]; then
        ZONE_SECTION_NAME=$s
        break
    fi
done
if [ -n "$ZONE_SECTION_NAME" ]; then
    uci delete firewall.$ZONE_SECTION_NAME
fi

# Find and delete the firewall forwarding rule by destination
FWD_SECTION_NAME=""
for s in $(uci show firewall | grep "=forwarding" | cut -d"." -f2); do
    if [ "$(uci -q get firewall.$s.dest)" = "awg1" ]; then
        FWD_SECTION_NAME=$s
        break
    fi
done
if [ -n "$FWD_SECTION_NAME" ]; then
    uci delete firewall.$FWD_SECTION_NAME
fi

uci commit firewall
/etc/init.d/firewall reload >/dev/null 2>&1

# 3. Uninstall all related packages
echo "Removing installed packages..."
opkg remove luci-proto-amneziawg luci-app-amneziawg amneziawg-tools kmod-amneziawg luci-i18n-amneziawg-ru >/dev/null 2>&1 || true

# 4. Restart network service to apply changes
echo "Restarting network service..."
/etc/init.d/network restart >/dev/null 2>&1

# 5. Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf /tmp/amneziawg

echo "AmneziaWG has been completely uninstalled."

exit 0
