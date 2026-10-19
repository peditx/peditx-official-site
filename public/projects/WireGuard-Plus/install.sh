#!/bin/sh

# ==========================================
# OpenWrt Native WireGuard Setup + Passwall + UI Shortcut
# (Silent Mode - Status Reporting Only)
#
# Works on OpenWrt 23.05 / 24.10 (opkg) and 25.12+ (apk).
# The LuCI shortcut is menu.d JSON + a JS view — the old Lua controller
# is dead weight on 23/24 and does not exist at all on 25.12.
# ==========================================

printf '\n--- WireGuard-Plus By PeDitX ---\n\n'

# --- 1. USER CONFIGURATION (EDIT THIS) ---
WG_PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE"
WG_ADDRESS="10.10.10.2/32"
PEER_PUB_KEY="YOUR_PEER_PUBLIC_KEY_HERE"
ENDPOINT_HOST="example.com"
ENDPOINT_PORT="51820"
PRE_SHARED_KEY=""
WG_IFACE_NAME="wg_plus"
WG_ZONE_NAME="wg_zone"
NODE_LABEL="WG-Native-Direct"

# --- 2. PACKAGE MANAGER (23.05/24.10 = opkg, 25.12+ = apk, no opkg shim) ---
if command -v apk >/dev/null 2>&1; then
    PKG="apk"
    PKG_UPDATE="apk update"
    PKG_INSTALL="apk add"
elif command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    PKG_UPDATE="opkg update"
    PKG_INSTALL="opkg install"
else
    echo "ERROR: no supported package manager found (need opkg or apk)"
    exit 1
fi

# NOTE: OpenWrt 25.12 ships apk-tools 3.0.5, NOT Alpine's v2 — the Alpine
# cache-suppression flag is v2-only syntax and fails there. Plain `apk add`.
pkg_installed() {
    case "$PKG" in
        apk)  apk info -e "$1" >/dev/null 2>&1 ;;
        opkg) opkg status "$1" 2>/dev/null | grep -q '^Status:.*installed' ;;
    esac
}

# --- Helper Function for Status Reporting ---
report_status() {
    if [ "$1" -eq 0 ]; then
        echo " [OK] $2"
    else
        echo " [FAIL] $2"
        exit 1
    fi
}

# render <outfile>  <<'EOF' ... EOF
# Quoted heredoc + @MARKER@ substitution: the templates contain shell syntax
# the installer must not expand, and an empty variable would silently write
# an empty path into menu.d. Fail loudly instead.
render() {
    if [ -z "$WG_IFACE_NAME" ]; then
        echo "ERROR: render: WG_IFACE_NAME is empty"
        exit 1
    fi
    sed -e "s|@IFACE@|${WG_IFACE_NAME}|g" > "$1"
    if grep -q '@IFACE@' "$1"; then
        echo "ERROR: render: unsubstituted marker left in $1"
        exit 1
    fi
}

# --- 3. Prerequisites (install ONLY what is missing) ---
# Never re-install luci-base on a device that has it — a custom firmware's
# copy is load-bearing for the theme and every other app.
#
# luci-proto-wireguard is NOT optional: it ships protocol/wireguard.js, the
# LuCI protocol extension. Without it the Interfaces page shows
# "Unsupported protocol type / Install protocol extensions" and the wg
# interface cannot be managed at all.
install_prereqs() {
    MISSING=""
    for p in wireguard-tools kmod-wireguard luci-proto-wireguard; do
        pkg_installed "$p" || MISSING="$MISSING $p"
    done
    [ -z "$MISSING" ] && return 0

    $PKG_UPDATE >/dev/null 2>&1

    # One package at a time: apk aborts the WHOLE transaction when a single
    # name is unknown, so a batch would drop all three on one missing name.
    #
    # Do NOT trust the exit code. Observed on real PeDitXOS 25.12
    # (apk-tools 3.0.5): `apk add` prints a spurious
    # "1 error; ... MiB in ... packages" summary and can return non-zero
    # even when the package installed fine. So: attempt once silently, then
    # judge by INSTALLED STATE. Only retry verbosely when it genuinely did
    # not land, so the real error is what the user sees.
    FAILED=""
    for p in $MISSING; do
        $PKG_INSTALL "$p" >/dev/null 2>&1
        pkg_installed "$p" && continue
        $PKG_INSTALL "$p"
        pkg_installed "$p" || FAILED="$FAILED $p"
    done

    if [ -n "$FAILED" ]; then
        echo "ERROR: could not install:$FAILED"
        echo "       Enable the 'luci' feed (luci-proto-wireguard lives there)"
        echo "       and re-run. Without it the Interfaces page cannot"
        echo "       manage $WG_IFACE_NAME."
        return 1
    fi
    return 0
}

install_prereqs
report_status $? "Prerequisites Check/Install"

# --- 3b. Make netifd actually know the wireguard protocol ---
# netifd scans /lib/netifd/proto/ ONCE, at startup. wireguard-tools drops
# proto/wireguard.sh there, so if that package was installed after netifd
# booted, the handler is on disk but never registered. `network reload`
# does NOT rescan it — only a restart does. Symptoms when missing:
# LuCI Interfaces shows "Unsupported protocol type / Install protocol
# extensions" even though luci-proto-wireguard is installed.
#
# NOTE: only CALLED at the very end of the installer — restarting netifd
# mid-config would bring it up before our UCI changes are committed.
netifd_has_wireguard() {
    ubus call network get_proto_handlers 2>/dev/null | grep -q '"wireguard"'
}

ensure_netifd_proto() {
    netifd_has_wireguard && return 0

    echo " [INFO] netifd has not loaded the wireguard protocol handler yet."

    # Detached on purpose: restarting network drops every interface,
    # which usually kills the very SSH session running this installer.
    # setsid + nohup + the parent exiting lets the restart finish anyway,
    # and the follow-up reload re-reads our committed config.
    ( setsid nohup sh -c '
        /etc/init.d/network restart >/dev/null 2>&1
        sleep 8
        /etc/init.d/network reload  >/dev/null 2>&1
      ' >/dev/null 2>&1 & ) 2>/dev/null

    echo " [WARN] Network is restarting to pick up the wireguard handler."
    echo "        Your SSH/browser session may drop for a few seconds."
    echo "        Re-open LuCI -> Network -> Interfaces afterwards."
    return 0
}

# --- 4. Network Configuration ---
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

# --- 5. Firewall Configuration ---
configure_firewall() {
    CHANGED=0

    if ! uci show firewall | grep -q "name='$WG_ZONE_NAME'"; then
        ZONE_KEY=$(uci add firewall zone)
        if [ -z "$ZONE_KEY" ]; then return 1; fi

        uci set firewall.$ZONE_KEY.name="$WG_ZONE_NAME"
        uci set firewall.$ZONE_KEY.input='REJECT'
        uci set firewall.$ZONE_KEY.output='ACCEPT'
        uci set firewall.$ZONE_KEY.forward='REJECT'
        uci set firewall.$ZONE_KEY.masq='1'
        uci set firewall.$ZONE_KEY.mtu_fix='1'
        uci add_list firewall.$ZONE_KEY.network="$WG_IFACE_NAME"
        CHANGED=1
    fi

    # Checked separately: a half-finished earlier run must be repairable
    if ! uci show firewall | grep -q "dest='$WG_ZONE_NAME'"; then
        FWD_KEY=$(uci add firewall forwarding)
        if [ -z "$FWD_KEY" ]; then return 1; fi

        uci set firewall.$FWD_KEY.src='lan'
        uci set firewall.$FWD_KEY.dest="$WG_ZONE_NAME"
        CHANGED=1
    fi

    [ "$CHANGED" -eq 1 ] && uci commit firewall
    return 0
}

configure_firewall >/dev/null 2>&1
report_status $? "Firewall Configuration"

# --- 6. Passwall Configuration ---
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

# --- 7. LuCI Shortcut (menu.d JSON + JS view — identical on 23.05/24.10/25.12) ---
MENU_D="/usr/share/luci/menu.d/luci-app-wg-shortcut.json"
VIEW_DIR="/www/luci-static/resources/view/wgplus"
LEGACY_LUA="/usr/lib/lua/luci/controller/wg_shortcut.lua"

install_shortcut() {
    # LuCI present?
    [ -d /usr/share/luci/menu.d ] || [ -d /www/luci-static/resources ] || return 1

    mkdir -p /usr/share/luci/menu.d "$VIEW_DIR"

    # Our own previous file must not count as "someone owns admin/vpn"
    rm -f "$MENU_D"

    # admin/vpn is usually owned by luci-app-openvpn & friends. Contribute
    # only the child node when it already exists — a second parent owner
    # merges unpredictably and can hide the whole branch.
    if grep -qs '"admin/vpn"' /usr/share/luci/menu.d/*.json; then
        render "$MENU_D" << 'JSONEOF'
{
	"admin/vpn/wg_native": {
		"title": "WireGuard Config",
		"order": 20,
		"action": { "type": "view", "path": "wgplus/main" }
	}
}
JSONEOF
    else
        render "$MENU_D" << 'JSONEOF'
{
	"admin/vpn": {
		"title": "VPN",
		"order": 45,
		"action": { "type": "firstchild" }
	},
	"admin/vpn/wg_native": {
		"title": "WireGuard Config",
		"order": 20,
		"action": { "type": "view", "path": "wgplus/main" }
	}
}
JSONEOF
    fi

    # JS view: jump to Network -> Interfaces, the target the old Lua
    # controller redirected to. interfaces.js does not deep-link to a single
    # interface on any of 23.05 / 24.10 / 25.12, so land on the overview.
    #
    # LuCI view lifecycle: load() (fetch, no DOM) -> render() builds a
    # DETACHED tree that LuCI inserts afterwards. Therefore:
    #   - never document.getElementById() here (returns null -> blank page)
    #   - there is no pollStart/onRender/ready hook; unknown methods are
    #     simply never called.
    render "$VIEW_DIR/main.js" << 'JSEOF'
'use strict';
'require view';

return view.extend({
	load: function() {
		return Promise.resolve();
	},

	render: function() {
		/* let the view mount, then navigate away */
		window.setTimeout(function() {
			window.location.replace(L.url('admin/network/network'));
		}, 0);

		return E('div', {}, _('Redirecting to Network → Interfaces (@IFACE@) …'));
	},

	/* hide LuCI's own footer bar — this page has nothing to save */
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
JSEOF

    # Drop the old Lua shortcut from a previous install: dead on 25.12
    # (no Lua runtime) and unused clutter on 23/24.
    rm -f "$LEGACY_LUA"

    # Clear all three LuCI caches (ucode LuCI caches modules too)
    rm -f /tmp/luci-indexcache /tmp/luci-sessions/.root 2>/dev/null
    rm -rf /tmp/luci-modulecache 2>/dev/null
    return 0
}

install_shortcut
if [ $? -eq 0 ]; then
    echo " [OK] Menu Shortcut Created (VPN -> WireGuard Config)"
else
    echo " [INFO] LuCI not found, shortcut skipped."
fi

# --- 8. Reload Services ---
# reload, not restart: a restart drops every interface (and the admin's
# remote session) while netifd/fw reload pick up the new config in place.
# The ONE exception is ensure_netifd_proto() below, which must restart
# because netifd never rescans /lib/netifd/proto/ on a reload.
reload_services() {
    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1
}

if netifd_has_wireguard; then
    reload_services
    report_status $? "Service Reload"
else
    # skip the plain reload — ensure_netifd_proto() is about to restart
    # netifd anyway, and a reload racing that restart would just be noise
    ensure_netifd_proto
    report_status 0 "Service Reload (netifd restart dispatched)"
fi
