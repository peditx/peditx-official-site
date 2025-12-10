#!/bin/sh

# ==========================================
# OpenWrt Native IKEv2 Setup + Passwall + UI Shortcut
# (Silent Mode - Tun Device Fix & Bulletproof Restart)
# ==========================================

echo -e "\n--- IKEv2-Plus By PeDitX ---\n"

# --- 1. USER CONFIGURATION (EDIT THIS) ---
IKEV2_SERVER="vpn.example.com"
IKEV2_USER="my_username"
IKEV2_PASS="my_password"

# Naming Constants
IKEV2_DEV_NAME="ipsec0"   # Created by kernel-libipsec
IKEV2_IFACE_NAME="ikev2_plus"
IKEV2_ZONE_NAME="ikev2_zone"
NODE_LABEL="IKEv2-Native-Direct"

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
    # Core StrongSwan packages
    if ! is_installed "strongswan-default"; then NEED_INSTALL=1; fi
    if ! is_installed "strongswan-mod-eap-mschapv2"; then NEED_INSTALL=1; fi
    if ! is_installed "strongswan-mod-eap-identity"; then NEED_INSTALL=1; fi
    if ! is_installed "strongswan-mod-kernel-libipsec"; then NEED_INSTALL=1; fi
    # Ensure TUN driver is present (Critical for kernel-libipsec)
    if ! is_installed "kmod-tun"; then NEED_INSTALL=1; fi

    if [ "$NEED_INSTALL" -eq 1 ]; then
        echo "Installing missing packages..."
        opkg update >/dev/null 2>&1
        opkg install strongswan-default strongswan-mod-eap-mschapv2 strongswan-mod-eap-identity strongswan-mod-kernel-libipsec kmod-tun >/dev/null 2>&1
        return $?
    fi
    return 0
}

install_prereqs
report_status $? "Prerequisites Check/Install (IKEv2)"

# --- 2.5 Ensure TUN Device is Available (CRITICAL FIX) ---
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
    
    # Verify if we can access it
    if [ -c /dev/net/tun ]; then
        return 0
    else
        return 1
    fi
}

check_tun_device
report_status $? "TUN Device Check"

# --- 3. Configure StrongSwan (ipsec.conf) ---
configure_ipsec() {
    mkdir -p /etc/ipsec.d

    # Backup existing config SAFELY
    if [ -f /etc/ipsec.conf ] && [ ! -f /etc/ipsec.conf.bak ]; then
        cp /etc/ipsec.conf /etc/ipsec.conf.bak
    fi

    if [ -f /etc/ipsec.secrets ] && [ ! -f /etc/ipsec.secrets.bak ]; then
        cp /etc/ipsec.secrets /etc/ipsec.secrets.bak
    fi

    # Write ipsec.conf
    cat <<EOF > /etc/ipsec.conf
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn %default
    ikelifetime=60m
    keylife=20m
    rekeymargin=3m
    keyingtries=1
    keyexchange=ikev2

conn ikev2_client
    left=%defaultroute
    leftsourceip=%config
    leftauth=eap-mschapv2
    eap_identity="$IKEV2_USER"
    right=$IKEV2_SERVER
    rightauth=pubkey
    rightsubnet=0.0.0.0/0
    rightid=%any
    auto=start
    type=tunnel
EOF

    # Write ipsec.secrets
    cat <<EOF > /etc/ipsec.secrets
# user : EAP "password"
$IKEV2_USER : EAP "$IKEV2_PASS"
EOF
}

configure_ipsec
report_status $? "StrongSwan Configuration"

# --- 4. Network Configuration ---
configure_network() {
    uci delete network.$IKEV2_IFACE_NAME >/dev/null 2>&1
    
    uci set network.$IKEV2_IFACE_NAME=interface
    uci set network.$IKEV2_IFACE_NAME.proto='none'
    uci set network.$IKEV2_IFACE_NAME.device="$IKEV2_DEV_NAME"
    
    uci commit network
}

configure_network >/dev/null 2>&1
report_status $? "Network Configuration"

# --- 5. Firewall Configuration ---
configure_firewall() {
    if ! uci show firewall | grep -q "name='$IKEV2_ZONE_NAME'"; then
        
        ZONE_KEY=$(uci add firewall zone)
        if [ -z "$ZONE_KEY" ]; then return 1; fi
        
        uci set firewall.$ZONE_KEY.name="$IKEV2_ZONE_NAME"
        uci set firewall.$ZONE_KEY.input='REJECT'
        uci set firewall.$ZONE_KEY.output='ACCEPT'
        uci set firewall.$ZONE_KEY.forward='REJECT'
        uci set firewall.$ZONE_KEY.masq='1'
        uci set firewall.$ZONE_KEY.mtu_fix='1'
        uci add_list firewall.$ZONE_KEY.network="$IKEV2_IFACE_NAME"
        
        FWD_KEY=$(uci add firewall forwarding)
        if [ -z "$FWD_KEY" ]; then return 1; fi

        uci set firewall.$FWD_KEY.src='lan'
        uci set firewall.$FWD_KEY.dest="$IKEV2_ZONE_NAME"
        
        uci commit firewall
    fi
}

configure_firewall >/dev/null 2>&1
report_status $? "Firewall Configuration"

# --- 6. Passwall Configuration ---
configure_passwall() {
    FOUND=0
    
    add_node() {
        CFG=$1
        NODE="ikev2_native_node"
        uci delete $CFG.$NODE >/dev/null 2>&1
        uci set $CFG.$NODE=nodes
        uci set $CFG.$NODE.remarks="$NODE_LABEL"
        uci set $CFG.$NODE.type='Xray'
        uci set $CFG.$NODE.protocol='_iface'
        uci set $CFG.$NODE.iface="$IKEV2_DEV_NAME" 
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

# --- 7. Create LuCI Shortcut (VPN Menu) ---
configure_shortcut() {
    LUA_DIR="/usr/lib/lua/luci/controller"
    LUA_FILE="$LUA_DIR/ikev2_shortcut.lua"
    
    if [ -d "$LUA_DIR" ]; then
        cat <<EOF > "$LUA_FILE"
module("luci.controller.ikev2_shortcut", package.seeall)

function index()
    entry({"admin", "vpn"}, firstchild(), "VPN", 45).dependent = false
    entry({"admin", "vpn", "ikev2_native"}, call("action_redirect"), "IKEv2 Status", 40)
end

function action_redirect()
    -- Redirects to Network -> Interfaces -> ikev2_plus to check status
    luci.http.redirect(luci.dispatcher.build_url("admin", "network", "network", "$IKEV2_IFACE_NAME"))
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

# --- 8. Restart Services (WITH TUN CHECK) ---
restart_services() {
    # 1. Ensure TUN is ready (Just in case)
    check_tun_device >/dev/null 2>&1
    
    # 2. Network Reload (Safe)
    /etc/init.d/network reload >/dev/null 2>&1
    sleep 3
    
    # 3. Firewall Restart
    /etc/init.d/firewall restart >/dev/null 2>&1
    
    # 4. IPsec Clean Restart
    /etc/init.d/ipsec enable >/dev/null 2>&1
    
    # Force stop & kill stuck processes
    /etc/init.d/ipsec stop >/dev/null 2>&1
    killall -9 charon >/dev/null 2>&1
    sleep 2
    
    # Start fresh
    /etc/init.d/ipsec start >/dev/null 2>&1
    
    # 5. Verify
    sleep 2
    if pgrep charon >/dev/null; then
        return 0
    else
        # Fallback
        /etc/init.d/ipsec restart >/dev/null 2>&1
        sleep 2
        # Check again
        if pgrep charon >/dev/null; then
            return 0
        fi
        return 1
    fi
}

restart_services
report_status $? "Service Restart"
