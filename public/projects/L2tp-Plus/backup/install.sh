#!/bin/sh

# ==========================================
# OpenWrt Native L2TP Setup + Passwall + UI Shortcut
# (Silent Mode - Status Reporting Only)
# ==========================================

echo -e "\n--- L2TP-Plus By PeDitX ---\n"

# --- 1. USER CONFIGURATION (EDIT THIS) ---
L2TP_SERVER="l2tp.example.com"
L2TP_USER="my_username"
L2TP_PASS="my_password"

# Optional: Default Gateway metric
METRIC="0"

# Naming Constants
L2TP_IFACE_NAME="l2tp_plus"
L2TP_ZONE_NAME="l2tp_zone"
NODE_LABEL="L2TP-Native-Direct"

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
    # L2TP needs xl2tpd daemon and kernel modules
    if ! is_installed "xl2tpd"; then NEED_INSTALL=1; fi
    if ! is_installed "kmod-l2tp"; then NEED_INSTALL=1; fi
    # ppp-mod-pppol2tp is often required for kernel mode L2TP
    if ! is_installed "ppp-mod-pppol2tp"; then NEED_INSTALL=1; fi
    
    # Check for LuCI support (usually part of luci-proto-ppp or similar, but xl2tpd is core)
    # We install luci-proto-ppp just in case to ensure UI visibility
    if ! is_installed "luci-proto-ppp"; then NEED_INSTALL=1; fi

    if [ "$NEED_INSTALL" -eq 1 ]; then
        opkg update >/dev/null 2>&1
        opkg install xl2tpd kmod-l2tp ppp-mod-pppol2tp luci-proto-ppp >/dev/null 2>&1
        return $?
    fi
    return 0
}

install_prereqs
report_status $? "Prerequisites Check/Install (L2TP)"

# --- 3. Network Configuration ---
configure_network() {
    uci delete network.$L2TP_IFACE_NAME >/dev/null 2>&1
    
    uci set network.$L2TP_IFACE_NAME=interface
    uci set network.$L2TP_IFACE_NAME.proto='l2tp'
    uci set network.$L2TP_IFACE_NAME.server="$L2TP_SERVER"
    uci set network.$L2TP_IFACE_NAME.username="$L2TP_USER"
    uci set network.$L2TP_IFACE_NAME.password="$L2TP_PASS"
    uci set network.$L2TP_IFACE_NAME.metric="$METRIC"
    
    # Disable IPv6 to prevent leaks if not supported properly
    uci set network.$L2TP_IFACE_NAME.ipv6='0' 
    
    # Critical: Do not hijack all traffic (default route 0)
    uci set network.$L2TP_IFACE_NAME.defaultroute='0' 
    uci set network.$L2TP_IFACE_NAME.peerdns='0'
    
    # Keepalive settings (often helpful for L2TP stability)
    uci set network.$L2TP_IFACE_NAME.keepalive='10 60'

    uci commit network
}

configure_network >/dev/null 2>&1
report_status $? "Network Configuration"

# --- 4. Firewall Configuration ---
configure_firewall() {
    if ! uci show firewall | grep -q "name='$L2TP_ZONE_NAME'"; then
        
        ZONE_KEY=$(uci add firewall zone)
        if [ -z "$ZONE_KEY" ]; then return 1; fi
        
        uci set firewall.$ZONE_KEY.name="$L2TP_ZONE_NAME"
        uci set firewall.$ZONE_KEY.input='REJECT'
        uci set firewall.$ZONE_KEY.output='ACCEPT'
        uci set firewall.$ZONE_KEY.forward='REJECT'
        uci set firewall.$ZONE_KEY.masq='1'
        uci set firewall.$ZONE_KEY.mtu_fix='1'
        uci add_list firewall.$ZONE_KEY.network="$L2TP_IFACE_NAME"
        
        FWD_KEY=$(uci add firewall forwarding)
        if [ -z "$FWD_KEY" ]; then return 1; fi

        uci set firewall.$FWD_KEY.src='lan'
        uci set firewall.$FWD_KEY.dest="$L2TP_ZONE_NAME"
        
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
        NODE="l2tp_native_node"
        uci delete $CFG.$NODE >/dev/null 2>&1
        uci set $CFG.$NODE=nodes
        uci set $CFG.$NODE.remarks="$NODE_LABEL"
        
        # Direct Interface Binding
        uci set $CFG.$NODE.type='Xray'
        uci set $CFG.$NODE.protocol='_iface'
        uci set $CFG.$NODE.iface="$L2TP_IFACE_NAME"
        
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
    LUA_DIR="/usr/lib/lua/luci/controller"
    LUA_FILE="$LUA_DIR/l2tp_shortcut.lua"
    
    if [ -d "$LUA_DIR" ]; then
        cat <<EOF > "$LUA_FILE"
module("luci.controller.l2tp_shortcut", package.seeall)

function index()
    -- Create top-level "VPN" menu (Order 45) if not exists
    entry({"admin", "vpn"}, firstchild(), "VPN", 45).dependent = false

    -- Create the shortcut entry
    entry({"admin", "vpn", "l2tp_native"}, call("action_redirect"), "L2TP Config", 30)
end

function action_redirect()
    -- Redirects to Network -> Interfaces -> l2tp_plus
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "network", "$L2TP_IFACE_NAME"))
end
EOF
        
        rm -rf /tmp/luci-modulecache/ >/dev/null 2>&1
        rm -f /tmp/luci-indexcache >/dev/null 2>&1
        return 0
    else
        return 1
    fi
}

configure_shortcut
if [ $? -eq 0 ]; then
    echo " [OK] Menu Shortcut Created (VPN -> L2TP Config)"
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
