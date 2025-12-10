#!/bin/sh

# ==========================================
# OpenWrt OpenVPN Uninstaller
# (Safe Cleanup - Removes configs & legacy microsocks)
# ==========================================

echo -e "\n--- OpenVPN-Plus Uninstaller By PeDitX ---\n"

# --- Constants ---
OVPN_IFACE_NAME="ovpn_plus"
OVPN_ZONE_NAME="ovpn_zone"
NODE_ID="ovpn_native_node"

# --- Helper Function ---
report_status() {
    if [ "$1" -eq 0 ]; then
        echo " [OK] $2"
    else
        echo " [FAIL] $2"
    fi
}

echo "Starting safe uninstallation..."

# --- 1. Remove Passwall Node ---
remove_passwall_node() {
    if uci get passwall2.$NODE_ID >/dev/null 2>&1; then
        uci delete passwall2.$NODE_ID
        uci commit passwall2
        echo "   - Removed node from Passwall 2"
    fi

    if uci get passwall.$NODE_ID >/dev/null 2>&1; then
        uci delete passwall.$NODE_ID
        uci commit passwall
        echo "   - Removed node from Passwall"
    fi
}
remove_passwall_node
report_status $? "Passwall Cleanup"

# --- 2. Remove Network Interface ---
remove_network() {
    uci delete network.$OVPN_IFACE_NAME >/dev/null 2>&1
    uci commit network
}
remove_network
report_status $? "Network Interface Cleanup"

# --- 3. Remove Firewall Zone ---
remove_firewall() {
    for fwd in $(uci show firewall | grep "dest='$OVPN_ZONE_NAME'" | cut -d'.' -f1,2); do
        uci delete $fwd
    done
    for zone in $(uci show firewall | grep "name='$OVPN_ZONE_NAME'" | cut -d'.' -f1,2); do
        uci delete $zone
    done
    uci commit firewall
}
remove_firewall
report_status $? "Firewall Rules Cleanup"

# --- 4. Remove Legacy Microsocks (If exists) ---
remove_microsocks() {
    # Check if we previously set up microsocks on port 2012
    if opkg list-installed | grep -q "microsocks"; then
        echo "   - Found legacy Microsocks, removing..."
        /etc/init.d/microsocks stop >/dev/null 2>&1
        /etc/init.d/microsocks disable >/dev/null 2>&1
        uci delete microsocks >/dev/null 2>&1 # Reset config
        opkg remove microsocks >/dev/null 2>&1
    fi
}
remove_microsocks
report_status $? "Legacy Microsocks Cleanup"

# --- 5. Restart Services ---
restart_services() {
    echo "   - Restarting Network & Firewall..."
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}
restart_services
report_status $? "Service Restart"

echo -e "\n✅ Uninstallation Complete."
