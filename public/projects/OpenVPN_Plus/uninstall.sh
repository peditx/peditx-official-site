#!/bin/sh

# ==========================================
# OpenWrt OpenVPN Uninstaller
# (Safe Cleanup - Removes configs & legacy microsocks)
# ==========================================

printf '\n--- OpenVPN-Plus Uninstaller By PeDitX ---\n\n'

# --- Constants ---
OVPN_IFACE_NAME="ovpn_plus"
OVPN_ZONE_NAME="ovpn_zone"
NODE_ID="ovpn_native_node"

# --- Package manager (23.05/24.10 = opkg, 25.12+ = apk, no opkg shim) ---
# Only needed for the legacy microsocks removal; UCI cleanup runs either way
PKG=""
command -v apk  >/dev/null 2>&1 && PKG="apk"
command -v opkg >/dev/null 2>&1 && PKG="opkg"

pkg_installed() {
    case "$PKG" in
        apk)  apk info -e "$1" >/dev/null 2>&1 ;;
        opkg) opkg status "$1" 2>/dev/null | grep -q '^Status:.*installed' ;;
        *)    return 1 ;;
    esac
}

pkg_remove() {
    case "$PKG" in
        apk)  apk del "$@" >/dev/null 2>&1 ;;
        opkg) opkg remove "$@" >/dev/null 2>&1 ;;
    esac
}

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
    # Delete the first match, re-read, repeat. `uci show` reports anonymous
    # sections as @type[N] and deleting one shifts every later index, so a
    # pre-built list of names would delete the wrong sections.
    while :; do
        SEC=$(uci show firewall 2>/dev/null \
            | grep -E "dest='$OVPN_ZONE_NAME'|name='$OVPN_ZONE_NAME'" \
            | head -n 1 | cut -d'.' -f1,2)
        [ -n "$SEC" ] || break
        uci -q delete "$SEC" || break
    done
    uci commit firewall
}
remove_firewall
report_status $? "Firewall Rules Cleanup"

# --- 4. Remove Legacy Microsocks (If exists) ---
remove_microsocks() {
    # Check if we previously set up microsocks on port 2012
    if pkg_installed microsocks; then
        echo "   - Found legacy Microsocks, removing..."
        /etc/init.d/microsocks stop >/dev/null 2>&1
        /etc/init.d/microsocks disable >/dev/null 2>&1
        uci -q delete microsocks # Reset config
        uci commit microsocks
        pkg_remove microsocks
    fi
}
remove_microsocks
report_status $? "Legacy Microsocks Cleanup"

# --- 5. Remove OpenVPN Packages (installed by install.sh) ---
# resolveip + kmod-tun stay: shared deps (ddns, passwall tun mode, zerotier...)
remove_openvpn() {
    pkg_installed openvpn-openssl || pkg_installed luci-app-openvpn || return 0
    echo "   - Removing OpenVPN packages (keeping resolveip + kmod-tun)..."
    /etc/init.d/openvpn stop >/dev/null 2>&1
    /etc/init.d/openvpn disable >/dev/null 2>&1
    pkg_remove luci-app-openvpn openvpn-openssl
}
remove_openvpn
report_status $? "OpenVPN Package Cleanup"

# --- 6. Reload Services ---
# reload, not restart: a restart drops every interface (and the admin's
# remote session) while netifd/fw reload apply the cleanup in place
reload_services() {
    echo "   - Reloading Network & Firewall..."
    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1
}
reload_services
report_status $? "Service Reload"

printf '\n✅ Uninstallation Complete.\n'
