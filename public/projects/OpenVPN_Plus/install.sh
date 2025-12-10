#!/bin/sh

# ==========================================
# OpenWrt Native OpenVPN Setup + Passwall
# (Silent Mode - Direct Interface Method)
# ==========================================

echo -e "\n--- OpenVPN-Plus By PeDitX ---\n"

# --- Constants ---
OVPN_DEV_NAME="tun0"
OVPN_IFACE_NAME="ovpn_plus"
OVPN_ZONE_NAME="ovpn_zone"
NODE_LABEL="OpenVPN-Native-Direct"

# --- Helper Function for Status Reporting ---
report_status() {
    if [ "$1" -eq 0 ]; then
        echo " [OK] $2"
    else
        echo " [FAIL] $2"
        exit 1
    fi
}

# --- 1. Prerequisites (Updated to include kmod-tun) ---
install_prereqs() {
    is_installed() {
        opkg list-installed | grep -q "^$1"
    }
    
    NEED_INSTALL=0
    if ! is_installed "openvpn-openssl"; then NEED_INSTALL=1; fi
    if ! is_installed "luci-app-openvpn"; then NEED_INSTALL=1; fi
    if ! is_installed "resolveip"; then NEED_INSTALL=1; fi
    # Critical: Kernel module for TUN/TAP devices
    if ! is_installed "kmod-tun"; then NEED_INSTALL=1; fi

    if [ "$NEED_INSTALL" -eq 1 ]; then
        echo "Installing missing packages (including kmod-tun)..."
        opkg update >/dev/null 2>&1
        opkg install openvpn-openssl luci-app-openvpn resolveip kmod-tun >/dev/null 2>&1
        return $?
    fi
    return 0
}

install_prereqs
report_status $? "Prerequisites Check/Install (OpenVPN)"

# --- 1.5 Ensure TUN Device is Available ---
check_tun_device() {
    # Try to load the kernel module
    if [ -f /sbin/modprobe ]; then
        /sbin/modprobe tun >/dev/null 2>&1
    elif [ -f /usr/sbin/modprobe ]; then
        /usr/sbin/modprobe tun >/dev/null 2>&1
    fi

    # Check/Create the device node if missing
    if [ ! -e /dev/net/tun ]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200
        chmod 600 /dev/net/tun
    fi
    
    # Verify if we can access it (even if busy, it should exist)
    if [ -c /dev/net/tun ]; then
        return 0
    else
        return 1
    fi
}

check_tun_device
report_status $? "TUN/TAP Device Check"

# --- 2. Network Configuration ---
configure_network() {
    # We create a logical interface that points to the tun0 device.
    uci delete network.$OVPN_IFACE_NAME >/dev/null 2>&1
    
    uci set network.$OVPN_IFACE_NAME=interface
    uci set network.$OVPN_IFACE_NAME.proto='none'
    uci set network.$OVPN_IFACE_NAME.device="$OVPN_DEV_NAME"
    
    uci commit network
}

configure_network >/dev/null 2>&1
report_status $? "Network Configuration"

# --- 3. Firewall Configuration ---
configure_firewall() {
    if ! uci show firewall | grep -q "name='$OVPN_ZONE_NAME'"; then
        
        ZONE_KEY=$(uci add firewall zone)
        if [ -z "$ZONE_KEY" ]; then return 1; fi
        
        uci set firewall.$ZONE_KEY.name="$OVPN_ZONE_NAME"
        uci set firewall.$ZONE_KEY.input='REJECT'
        uci set firewall.$ZONE_KEY.output='ACCEPT'
        uci set firewall.$ZONE_KEY.forward='REJECT'
        uci set firewall.$ZONE_KEY.masq='1'
        uci set firewall.$ZONE_KEY.mtu_fix='1'
        uci add_list firewall.$ZONE_KEY.network="$OVPN_IFACE_NAME"
        
        FWD_KEY=$(uci add firewall forwarding)
        if [ -z "$FWD_KEY" ]; then return 1; fi

        uci set firewall.$FWD_KEY.src='lan'
        uci set firewall.$FWD_KEY.dest="$OVPN_ZONE_NAME"
        
        uci commit firewall
    fi
}

configure_firewall >/dev/null 2>&1
report_status $? "Firewall Configuration"

# --- 4. Passwall Configuration ---
configure_passwall() {
    FOUND=0
    
    add_node() {
        CFG=$1
        NODE="ovpn_native_node"
        uci delete $CFG.$NODE >/dev/null 2>&1
        uci set $CFG.$NODE=nodes
        uci set $CFG.$NODE.remarks="$NODE_LABEL"
        
        # Direct Interface Binding
        uci set $CFG.$NODE.type='Xray'
        uci set $CFG.$NODE.protocol='_iface'
        uci set $CFG.$NODE.iface="$OVPN_DEV_NAME" 
        
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

# --- 5. Restart Services ---
restart_services() {
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/firewall restart >/dev/null 2>&1
}

restart_services
report_status $? "Service Restart"

echo -e "\nℹ️  Next Step: Go to VPN -> OpenVPN and upload your .ovpn config file."
