#!/bin/sh

# ==========================================
# OpenWrt Native L2TP Uninstaller
# (Safe Cleanup - Removes only created configs & Shortcuts)
# ==========================================

echo -e "\n--- L2TP-Plus Uninstaller By PeDitX ---\n"

# --- Constants (Must match the installer) ---
L2TP_IFACE_NAME="l2tp_plus"
L2TP_ZONE_NAME="l2tp_zone"
NODE_ID="l2tp_native_node"
LUA_SHORTCUT="/usr/lib/lua/luci/controller/l2tp_shortcut.lua"

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
    uci delete network.$L2TP_IFACE_NAME >/dev/null 2>&1
    uci commit network
}

remove_network
report_status $? "Network Interface Cleanup"

# --- 3. Remove Firewall Zone & Forwarding ---
remove_firewall() {
    for fwd in $(uci show firewall | grep "dest='$L2TP_ZONE_NAME'" | cut -d'.' -f1,2); do
        uci delete $fwd
    done

    for zone in $(uci show firewall | grep "name='$L2TP_ZONE_NAME'" | cut -d'.' -f1,2); do
        uci delete $zone
    done

    uci commit firewall
}

remove_firewall
report_status $? "Firewall Rules Cleanup"

# --- 4. Remove LuCI Shortcut & Cache ---
remove_shortcut() {
    if [ -f "$LUA_SHORTCUT" ]; then
        rm -f "$LUA_SHORTCUT"
        echo "   - Removed VPN menu shortcut"
    fi
    
    rm -rf /tmp/luci-modulecache/ >/dev/null 2>&1
    rm -f /tmp/luci-indexcache >/dev/null 2>&1
}

remove_shortcut
report_status $? "UI Shortcut & Cache Cleanup"

# --- 5. Restart Services ---
restart_services() {
    echo "   - Restarting Network & Firewall..."
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}

restart_services
report_status $? "Service Restart"

echo -e "\n✅ Uninstallation Complete. System clean."
