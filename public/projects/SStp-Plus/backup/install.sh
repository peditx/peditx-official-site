#!/bin/sh

# ==========================================
# OpenWrt Native SSTP Setup + Passwall + UI Shortcut
# (Silent Mode - Status Reporting Only)
# ==========================================

echo -e "\n--- SSTP-Plus By PeDitX ---\n"

# --- 1. USER CONFIGURATION (EDIT THIS) ---
SSTP_SERVER="vpne.example.com"
SSTP_USER="my_username"
SSTP_PASS="my_password"

# Optional: Default Gateway metric (usually 0 is fine for VPN)
METRIC="0"

# Naming Constants
SSTP_IFACE_NAME="sstp_plus"
SSTP_ZONE_NAME="sstp_zone"
NODE_LABEL="SSTP-Native-Direct"

# --- Helper Function for Status Reporting ---
report_status() {
    if [ "$1" -eq 0 ]; then
        echo " [OK] $2"
    else
        echo " [FAIL] $2"
        exit 1
    fi
}

# --- 2. Prerequisites ---
install_prereqs() {
    is_installed() {
        opkg list-installed | grep -q "^$1"
    }
    
    NEED_INSTALL=0
    # SSTP requires sstp-client and the luci protocol handler
    if ! is_installed "sstp-client"; then NEED_INSTALL=1; fi
    if ! is_installed "luci-proto-sstp"; then NEED_INSTALL=1; fi
    # kmod-mppe is often needed for encryption
    if ! is_installed "kmod-mppe"; then NEED_INSTALL=1; fi

    if [ "$NEED_INSTALL" -eq 1 ]; then
        opkg update >/dev/null 2>&1
        opkg install sstp-client luci-proto-sstp kmod-mppe >/dev/null 2>&1
        return $?
    fi
    return 0
}

install_prereqs
report_status $? "Prerequisites Check/Install (SSTP)"

# --- 3. Network Configuration ---
configure_network() {
    uci delete network.$SSTP_IFACE_NAME >/dev/null 2>&1
    
    uci set network.$SSTP_IFACE_NAME=interface
    uci set network.$SSTP_IFACE_NAME.proto='sstp'
    uci set network.$SSTP_IFACE_NAME.server="$SSTP_SERVER"
    uci set network.$SSTP_IFACE_NAME.username="$SSTP_USER"
    uci set network.$SSTP_IFACE_NAME.password="$SSTP_PASS"
    uci set network.$SSTP_IFACE_NAME.metric="$METRIC"
    
    # Enable IPv6 if available, or disable if causing leaks
    uci set network.$SSTP_IFACE_NAME.ipv6='0' 
    
    # Critical: Do not use default gateway automatically, let Passwall handle routing
    uci set network.$SSTP_IFACE_NAME.defaultroute='0' 
    uci set network.$SSTP_IFACE_NAME.peerdns='0'

    uci commit network
}

configure_network >/dev/null 2>&1
report_status $? "Network Configuration"

# --- 4. Firewall Configuration ---
configure_firewall() {
    if ! uci show firewall | grep -q "name='$SSTP_ZONE_NAME'"; then
        
        ZONE_KEY=$(uci add firewall zone)
        if [ -z "$ZONE_KEY" ]; then return 1; fi
        
        uci set firewall.$ZONE_KEY.name="$SSTP_ZONE_NAME"
        uci set firewall.$ZONE_KEY.input='REJECT'
        uci set firewall.$ZONE_KEY.output='ACCEPT'
        uci set firewall.$ZONE_KEY.forward='REJECT'
        uci set firewall.$ZONE_KEY.masq='1'
        uci set firewall.$ZONE_KEY.mtu_fix='1'
        uci add_list firewall.$ZONE_KEY.network="$SSTP_IFACE_NAME"
        
        FWD_KEY=$(uci add firewall forwarding)
        if [ -z "$FWD_KEY" ]; then return 1; fi

        uci set firewall.$FWD_KEY.src='lan'
        uci set firewall.$FWD_KEY.dest="$SSTP_ZONE_NAME"
        
        uci commit firewall
    fi
}

configure_firewall >/dev/null 2>&1
report_status $? "Firewall Configuration"

# --- 5. Passwall Configuration ---
configure_passwall() {
    FOUND=0
    
    add_node() {
        CFG=$1
        NODE="sstp_native_node"
        uci delete $CFG.$NODE >/dev/null 2>&1
        uci set $CFG.$NODE=nodes
        uci set $CFG.$NODE.remarks="$NODE_LABEL"
        
        # Direct Interface Binding
        uci set $CFG.$NODE.type='Xray'
        uci set $CFG.$NODE.protocol='_iface'
        uci set $CFG.$NODE.iface="$SSTP_IFACE_NAME"
        
        uci commit $CFG
    }

    if uci show passwall2 >/dev/null 2>&1; then
        add_node "passwall2"
        FOUND=1
    fi

    if uci show passwall >/dev/null 2>&1; then
        add_node "passwall"
        FOUND=1
    fi
    
    if [ "$FOUND" -eq 0 ]; then
        return 1
    fi
    return 0
}

configure_passwall >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo " [OK] Passwall Configuration"
else
    echo " [WARN] Passwall not found (Skipped)"
fi

# --- 6. Create LuCI Shortcut (VPN Menu) ---
configure_shortcut() {
    # Path where LuCI controllers live
    LUA_DIR="/usr/lib/lua/luci/controller"
    LUA_FILE="$LUA_DIR/sstp_shortcut.lua"
    
    # Only proceed if LuCI is installed
    if [ -d "$LUA_DIR" ]; then
        # Create the Lua script for the menu
        cat <<EOF > "$LUA_FILE"
module("luci.controller.sstp_shortcut", package.seeall)

function index()
    -- 1. Create top-level "VPN" menu (if it doesn't exist, this creates it)
    -- Order 45 puts it usually after Network/Services
    entry({"admin", "vpn"}, firstchild(), "VPN", 45).dependent = false

    -- 2. Create the shortcut entry
    entry({"admin", "vpn", "sstp_native"}, call("action_redirect"), "SSTP Config", 10)
end

function action_redirect()
    -- Redirects to Network -> Interfaces -> sstp_plus
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "network", "$SSTP_IFACE_NAME"))
end
EOF
        
        # Clear LuCI cache to make the menu appear immediately
        rm -rf /tmp/luci-modulecache/ >/dev/null 2>&1
        rm -f /tmp/luci-indexcache >/dev/null 2>&1
        return 0
    else
        return 1
    fi
}

configure_shortcut
# We don't fail script if LuCI isn't there (maybe it's a headless router)
if [ $? -eq 0 ]; then
    echo " [OK] Menu Shortcut Created (VPN -> SSTP Config)"
else
    echo " [INFO] LuCI not found, shortcut skipped."
fi

# --- 7. Restart Services ---
restart_services() {
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}

restart_services
report_status $? "Service Restart"
