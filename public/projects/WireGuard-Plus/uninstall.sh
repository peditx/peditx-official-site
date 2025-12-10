#!/bin/sh

# ==========================================
# OpenWrt Native WireGuard Uninstaller
# (Safe Cleanup - Removes only created configs)
# ==========================================

echo -e "\n--- WireGuard-Plus Uninstaller By PeDitX ---\n"

# --- Constants (Must match the installer) ---
WG_IFACE_NAME="wg_plus"
WG_ZONE_NAME="wg_zone"
NODE_ID="wg_native_node"

# --- Helper Function for Status Reporting ---
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
    # Check Passwall 2
    if uci get passwall2.$NODE_ID >/dev/null 2>&1; then
        uci delete passwall2.$NODE_ID
        uci commit passwall2
        echo "   - Removed node from Passwall 2"
    fi

    # Check Regular Passwall
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
    # Remove the Interface
    uci delete network.$WG_IFACE_NAME >/dev/null 2>&1
    
    # Remove the Peer (We named it specifically in the installer)
    PEER_ID="wireguard_${WG_IFACE_NAME}"
    uci delete network.$PEER_ID >/dev/null 2>&1
    
    uci commit network
}

remove_network
report_status $? "Network Interface Cleanup"

# --- 3. Remove Firewall Zone & Forwarding ---
remove_firewall() {
    # 3.1 Remove Forwardings pointing to our zone
    # We grep for the destination name to find the section ID (e.g., firewall.@forwarding[0])
    for fwd in $(uci show firewall | grep "dest='$WG_ZONE_NAME'" | cut -d'.' -f1,2); do
        uci delete $fwd
    done

    # 3.2 Remove the Zone itself
    # We grep for the zone name to find the section ID (e.g., firewall.@zone[1])
    for zone in $(uci show firewall | grep "name='$WG_ZONE_NAME'" | cut -d'.' -f1,2); do
        uci delete $zone
    done

    uci commit firewall
}

remove_firewall
report_status $? "Firewall Rules Cleanup"

# --- 4. Restart Services ---
restart_services() {
    echo "   - Restarting Network & Firewall..."
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}

restart_services
report_status $? "Service Restart"

echo -e "\n✅ Uninstallation Complete. System clean."
