#!/bin/sh

# ==========================================
# OpenWrt IKEv2 Uninstaller
# (Safe Cleanup)
# ==========================================

echo -e "\n--- IKEv2-Plus Uninstaller By PeDitX ---\n"

# --- Constants ---
IKEV2_IFACE_NAME="ikev2_plus"
IKEV2_ZONE_NAME="ikev2_zone"
NODE_ID="ikev2_native_node"
LUA_SHORTCUT="/usr/lib/lua/luci/controller/ikev2_shortcut.lua"

# --- Helper Function ---
report_status() {
    if [ "$1" -eq 0 ]; then
        echo " [OK] $2"
    else
        echo " [FAIL] $2"
    fi
}

echo "Starting safe uninstallation..."

# --- 1. Restore StrongSwan Config ---
restore_ipsec() {
    # If backup exists, restore it. If not, just empty the files to be safe
    if [ -f /etc/ipsec.conf.bak ]; then
        mv /etc/ipsec.conf.bak /etc/ipsec.conf
        mv /etc/ipsec.secrets.bak /etc/ipsec.secrets
        echo "   - Restored original ipsec.conf/secrets"
    else
        # Basic cleanup if no backup
        > /etc/ipsec.secrets
        cat <<EOF > /etc/ipsec.conf
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no
EOF
        echo "   - Reset ipsec.conf to defaults"
    fi
    
    /etc/init.d/ipsec restart >/dev/null 2>&1
}
restore_ipsec
report_status $? "StrongSwan Config Cleanup"

# --- 2. Remove Passwall Node ---
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

# --- 3. Remove Network Interface ---
remove_network() {
    uci delete network.$IKEV2_IFACE_NAME >/dev/null 2>&1
    uci commit network
}
remove_network
report_status $? "Network Interface Cleanup"

# --- 4. Remove Firewall Zone ---
remove_firewall() {
    for fwd in $(uci show firewall | grep "dest='$IKEV2_ZONE_NAME'" | cut -d'.' -f1,2); do
        uci delete $fwd
    done
    for zone in $(uci show firewall | grep "name='$IKEV2_ZONE_NAME'" | cut -d'.' -f1,2); do
        uci delete $zone
    done
    uci commit firewall
}
remove_firewall
report_status $? "Firewall Rules Cleanup"

# --- 5. Remove LuCI Shortcut ---
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

# --- 6. Restart Services ---
restart_services() {
    echo "   - Restarting Network & Firewall..."
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}
restart_services
report_status $? "Service Restart"

echo -e "\n✅ Uninstallation Complete."
