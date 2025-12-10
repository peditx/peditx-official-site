#!/bin/sh

# ==========================================
# OpenWrt Native WireGuard Setup + Passwall
# (Silent Mode - Status Reporting Only)
# ==========================================

echo -e "\n--- WireGuard-Plus By PeDitX ---\n"

# --- 1. USER CONFIGURATION ---
WG_PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE"
WG_ADDRESS="10.10.10.2/32"
PEER_PUB_KEY="YOUR_PEER_PUBLIC_KEY_HERE"
ENDPOINT_HOST="example.com"
ENDPOINT_PORT="51820"
PRE_SHARED_KEY="" 
WG_IFACE_NAME="wg_plus"
WG_ZONE_NAME="wg_zone"
NODE_LABEL="WG-Native-Direct"

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
    if ! is_installed "wireguard-tools"; then NEED_INSTALL=1; fi
    if ! is_installed "luci-proto-wireguard"; then NEED_INSTALL=1; fi
    if ! is_installed "kmod-wireguard"; then NEED_INSTALL=1; fi

    if [ "$NEED_INSTALL" -eq 1 ]; then
        opkg update >/dev/null 2>&1
        opkg install wireguard-tools luci-proto-wireguard kmod-wireguard >/dev/null 2>&1
        return $?
    fi
    return 0
}

install_prereqs
report_status $? "Prerequisites Check/Install"

# --- 3. Network Configuration ---
configure_network() {
    uci delete network.$WG_IFACE_NAME >/dev/null 2>&1
    
    uci set network.$WG_IFACE_NAME=interface
    uci set network.$WG_IFACE_NAME.proto='wireguard'
    uci set network.$WG_IFACE_NAME.private_key="$WG_PRIVATE_KEY"
    uci add_list network.$WG_IFACE_NAME.addresses="$WG_ADDRESS"

    PEER_ID="wireguard_${WG_IFACE_NAME}"
    uci set network.$PEER_ID=wireguard_${WG_IFACE_NAME}
    uci set network.$PEER_ID.public_key="$PEER_PUB_KEY"
    uci set network.$PEER_ID.endpoint_host="$ENDPOINT_HOST"
    uci set network.$PEER_ID.endpoint_port="$ENDPOINT_PORT"
    uci set network.$PEER_ID.persistent_keepalive='25'
    uci set network.$PEER_ID.route_allowed_ips='0' 
    uci add_list network.$PEER_ID.allowed_ips="0.0.0.0/0"

    if [ ! -z "$PRE_SHARED_KEY" ]; then
        uci set network.$PEER_ID.preshared_key="$PRE_SHARED_KEY"
    fi

    uci commit network
}

configure_network >/dev/null 2>&1
report_status $? "Network Configuration"

# --- 4. Firewall Configuration ---
configure_firewall() {
    # Check if zone exists by looking for the name property
    if ! uci show firewall | grep -q "name='$WG_ZONE_NAME'"; then
        
        # Capture the ID directly from uci add command
        ZONE_KEY=$(uci add firewall zone)
        
        if [ -z "$ZONE_KEY" ]; then
            return 1
        fi
        
        uci set firewall.$ZONE_KEY.name="$WG_ZONE_NAME"
        uci set firewall.$ZONE_KEY.input='REJECT'
        uci set firewall.$ZONE_KEY.output='ACCEPT'
        uci set firewall.$ZONE_KEY.forward='REJECT'
        uci set firewall.$ZONE_KEY.masq='1'
        uci set firewall.$ZONE_KEY.mtu_fix='1'
        uci add_list firewall.$ZONE_KEY.network="$WG_IFACE_NAME"
        
        # Capture the ID directly for forwarding
        FWD_KEY=$(uci add firewall forwarding)
        
        if [ -z "$FWD_KEY" ]; then
             return 1
        fi

        uci set firewall.$FWD_KEY.src='lan'
        uci set firewall.$FWD_KEY.dest="$WG_ZONE_NAME"
        
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
        NODE="wg_native_node"
        uci delete $CFG.$NODE >/dev/null 2>&1
        uci set $CFG.$NODE=nodes
        uci set $CFG.$NODE.remarks="$NODE_LABEL"
        uci set $CFG.$NODE.type='Xray'
        uci set $CFG.$NODE.protocol='_iface'
        uci set $CFG.$NODE.iface="$WG_IFACE_NAME"
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

# --- 6. Restart Services ---
restart_services() {
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}

restart_services
report_status $? "Service Restart"
