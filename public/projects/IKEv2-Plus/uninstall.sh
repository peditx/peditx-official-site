#!/bin/sh

# ==========================================
# OpenWrt IKEv2 Uninstaller
# (Safe Cleanup)
# Works on OpenWrt 23.05 / 24.10 (opkg) and 25.12+ (apk).
# ==========================================

printf '\n--- IKEv2-Plus Uninstaller By PeDitX ---\n\n'

# --- Constants (Must match the installer) ---
IKEV2_IFACE_NAME="ikev2_plus"
IKEV2_ZONE_NAME="ikev2_zone"
NODE_ID="ikev2_native_node"
MENU_D="/usr/share/luci/menu.d/luci-app-ikev2-shortcut.json"
VIEW_DIR="/www/luci-static/resources/view/ikev2"
LEGACY_LUA="/usr/lib/lua/luci/controller/ikev2_shortcut.lua"

# Packages this app introduces. kmod-tun is DELIBERATELY absent: the TUN
# device is shared infrastructure (OpenVPN and the firmware itself use it),
# so it is not ours to remove.
IKEV2_PKGS="strongswan-default strongswan-ipsec strongswan-mod-eap-mschapv2 \
strongswan-mod-eap-identity strongswan-mod-kernel-libipsec"

# --- Package manager (23.05/24.10 = opkg, 25.12+ = apk) ---
if command -v apk >/dev/null 2>&1; then
    PKG="apk"
    PKG_REMOVE="apk del"
elif command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    PKG_REMOVE="opkg remove"
else
    PKG=""
    PKG_REMOVE=""
fi

pkg_installed() {
    case "$PKG" in
        apk)  apk info -e "$1" >/dev/null 2>&1 ;;
        opkg) opkg status "$1" 2>/dev/null | grep -q '^Status:.*installed' ;;
        *)    return 1 ;;
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

# --- 1. Restore StrongSwan Config ---
restore_ipsec() {
    # If backup exists, restore it. If not, just empty the files to be safe
    if [ -f /etc/ipsec.conf.bak ]; then
        mv /etc/ipsec.conf.bak /etc/ipsec.conf
        [ -f /etc/ipsec.secrets.bak ] && mv /etc/ipsec.secrets.bak /etc/ipsec.secrets
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
    return 0
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
    return 0
}

remove_passwall_node
report_status $? "Passwall Cleanup"

# --- 3. Remove Network Interface ---
remove_network() {
    uci delete network.$IKEV2_IFACE_NAME >/dev/null 2>&1
    uci commit network
    return 0
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
    return 0
}

remove_firewall
report_status $? "Firewall Rules Cleanup"

# --- 5. Remove LuCI Shortcut, legacy Lua & Caches ---
remove_shortcut() {
    if [ -f "$MENU_D" ]; then
        rm -f "$MENU_D"
        echo "   - Removed menu entry (VPN -> IKEv2 Status)"
    fi

    if [ -d "$VIEW_DIR" ]; then
        rm -rf "$VIEW_DIR"
        echo "   - Removed JS view"
    fi

    # Shortcut left behind by pre-2026 installs of this same app
    if [ -f "$LEGACY_LUA" ]; then
        rm -f "$LEGACY_LUA"
        echo "   - Removed legacy Lua controller"
    fi

    rm -rf /tmp/luci-modulecache/ >/dev/null 2>&1
    rm -f /tmp/luci-indexcache >/dev/null 2>&1
    return 0
}

remove_shortcut
report_status $? "UI Shortcut & Cache Cleanup"

# --- 6. Stop charon BEFORE removing the packages it lives in ---
stop_ipsec() {
    if [ -x /etc/init.d/ipsec ]; then
        /etc/init.d/ipsec stop >/dev/null 2>&1
    fi
    killall -9 charon >/dev/null 2>&1
    return 0
}

stop_ipsec
report_status $? "IPsec Service Stop"

# --- 7. Remove StrongSwan Packages ---
remove_packages() {
    if [ -z "$PKG" ]; then
        echo "   - No package manager found, packages left in place"
        return 0
    fi

    # strongswan-ipsec first: it is the leaf that owns /etc/init.d/ipsec
    for p in $IKEV2_PKGS; do
        if pkg_installed "$p"; then
            $PKG_REMOVE "$p" >/dev/null 2>&1 || $PKG_REMOVE "$p"
            # Do NOT trust the exit code — apk-tools 3.0.5 on OpenWrt 25.12
            # reports a spurious "1 error" summary and can return non-zero
            # on a successful removal. Re-check installed state instead.
            if pkg_installed "$p"; then
                echo "   - Could not remove $p (still required by another package?)"
            else
                echo "   - Removed package $p"
            fi
        fi
    done
    echo "   - kmod-tun kept (shared with other VPN apps / firmware)"
    return 0
}

remove_packages
report_status $? "StrongSwan Package Cleanup"

# --- 8. Reload Services ---
# reload, not restart: a restart drops every interface (and the admin's
# remote session) while netifd/fw reload pick up the change in place.
reload_services() {
    echo "   - Reloading Network & Firewall..."
    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1

    # If strongswan is still present (removal was refused), restart it so
    # the restored ipsec.conf actually takes effect.
    if [ -x /etc/init.d/ipsec ]; then
        echo "   - Restarting IPsec with the restored config..."
        /etc/init.d/ipsec start >/dev/null 2>&1
    fi
    return 0
}

reload_services
report_status $? "Service Reload"

printf '\n✅ Uninstallation Complete.\n'
