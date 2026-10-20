#!/bin/sh

# ==========================================
# OpenWrt Native L2TP Uninstaller
# (Safe Cleanup - Removes only created configs & Shortcuts)
# Works on OpenWrt 23.05 / 24.10 (opkg) and 25.12+ (apk).
# ==========================================

printf '\n--- L2TP-Plus Uninstaller By PeDitX ---\n\n'

# --- Constants (Must match the installer) ---
L2TP_IFACE_NAME="l2tp_plus"
L2TP_ZONE_NAME="l2tp_zone"
NODE_ID="l2tp_native_node"
MENU_D="/usr/share/luci/menu.d/luci-app-l2tp-shortcut.json"
VIEW_DIR="/www/luci-static/resources/view/l2tp"
LEGACY_LUA="/usr/lib/lua/luci/controller/l2tp_shortcut.lua"

# Packages this app introduces. luci-proto-ppp is DELIBERATELY absent: it also
# ships protocol/ppp.js, pppoe.js and pptp.js, i.e. the PPPoE WAN form the
# firmware itself may be built on — it is not ours to remove.
L2TP_PKGS="xl2tpd ppp-mod-pppol2tp kmod-l2tp"

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
    return 0
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

# --- 4. Remove LuCI Shortcut, legacy Lua & Caches ---
remove_shortcut() {
    if [ -f "$MENU_D" ]; then
        rm -f "$MENU_D"
        echo "   - Removed menu entry (VPN -> L2TP Config)"
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

# --- 5. Stop & disable xl2tpd ---
# Own init script (we enabled it in the installer), so stop it BEFORE the
# package goes away. No tunnel is left to serve: the interface is gone.
stop_daemon() {
    if [ -x /etc/init.d/xl2tpd ]; then
        /etc/init.d/xl2tpd stop >/dev/null 2>&1
        /etc/init.d/xl2tpd disable >/dev/null 2>&1
        echo "   - Stopped and disabled xl2tpd"
    fi
    return 0
}

stop_daemon

# --- 6. Remove L2TP Packages ---
remove_packages() {
    if [ -z "$PKG" ]; then
        echo "   - No package manager found, packages left in place"
        return 0
    fi

    # xl2tpd first: it depends on ppp-mod-pppol2tp and owns /etc/init.d/xl2tpd
    for p in $L2TP_PKGS; do
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
    echo "   - luci-proto-ppp kept (shared with the PPPoE/PPTP protocol forms)"
    return 0
}

remove_packages
report_status $? "L2TP Package Cleanup"

# --- 7. Make netifd FORGET the l2tp protocol ---
# Mirror image of the installer's netifd gotcha: netifd scans
# /lib/netifd/proto/ once at startup, so removing xl2tpd deletes
# proto/l2tp.sh from disk while netifd keeps the handler registered in
# memory. Without this, LuCI keeps offering "L2TP" in the protocol
# dropdown after uninstall and silently fails if picked. A reload does not
# re-scan either — only a restart does.
netifd_has_l2tp() {
    ubus call network get_proto_handlers 2>/dev/null | grep -q '"l2tp"'
}

ensure_netifd_forgets_proto() {
    # handler already gone from memory — nothing to do
    netifd_has_l2tp || return 0

    # script still on disk (removal failed or something else owns it):
    # restarting would just re-register it, so leave netifd alone
    [ -e /lib/netifd/proto/l2tp.sh ] && return 0

    echo "   - netifd still holds a stale l2tp handler, restarting it"

    # detached: the restart drops every interface, which kills this SSH
    # session. setsid + nohup + parent exit lets it finish anyway.
    ( setsid nohup sh -c '/etc/init.d/network restart >/dev/null 2>&1' \
        >/dev/null 2>&1 & ) 2>/dev/null

    echo "   - Your SSH/browser session may drop for a few seconds"
    return 0
}

ensure_netifd_forgets_proto

# --- 8. Reload Services ---
# reload, not restart: a restart drops every interface (and the admin's
# remote session) while netifd/fw reload pick up the change in place.
# The exception is the stale-handler case above, which already dispatched
# a restart.
reload_services() {
    echo "   - Reloading Network & Firewall..."
    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1
}

if netifd_has_l2tp && [ ! -e /lib/netifd/proto/l2tp.sh ]; then
    # a restart is already in flight; a racing reload would just be noise
    report_status 0 "Service Reload (netifd restart dispatched)"
else
    reload_services
    report_status $? "Service Reload"
fi

printf '\n✅ Uninstallation Complete. System clean.\n'
