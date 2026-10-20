#!/bin/sh

# ==========================================
# OpenWrt Native L2TP Setup + Passwall + UI Shortcut
# (Silent Mode - Status Reporting Only)
#
# Works on OpenWrt 23.05 / 24.10 (opkg) and 25.12+ (apk).
# The LuCI shortcut is menu.d JSON + a JS view — the old Lua controller
# is dead weight on 23/24 and does not exist at all on 25.12.
# ==========================================

printf '\n--- L2TP-Plus By PeDitX ---\n\n'

# --- 1. USER CONFIGURATION (EDIT THIS) ---
L2TP_SERVER="l2tp.example.com"
L2TP_USER="my_username"
L2TP_PASS="my_password"

# Optional: default-route metric of the tunnel. The tunnel itself never
# claims the default route (defaultroute=0 below) — it is a passwall node.
METRIC="0"

# Naming Constants
L2TP_IFACE_NAME="l2tp_plus"
L2TP_ZONE_NAME="l2tp_zone"
NODE_LABEL="L2TP-Native-Direct"

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
# Quoted heredoc + @MARKER@ substitution so an empty variable cannot silently
# write an empty path into the view text.
render() {
    if [ -z "$L2TP_IFACE_NAME" ]; then
        echo "ERROR: render: L2TP_IFACE_NAME is empty"
        exit 1
    fi
    sed -e "s|@IFACE@|${L2TP_IFACE_NAME}|g" > "$1"
    if grep -q '@IFACE@' "$1"; then
        echo "ERROR: render: unsubstituted marker left in $1"
        exit 1
    fi
}

# --- 3. Prerequisites (install ONLY what is missing) ---
# Never re-install luci-base on a device that has it — a custom firmware's
# copy is load-bearing for the theme and every other app. luci-base and rpcd
# are NOT reinstalled here: this app has no backend of its own, it only
# writes UCI + a redirect view.
#
# xl2tpd is NOT optional and is more than a daemon: its Makefile installs
#   /lib/netifd/proto/l2tp.sh  (netifd's l2tp protocol handler)
#   /usr/sbin/xl2tpd, /etc/init.d/xl2tpd, /etc/config/xl2tp
# and it already depends on ppp-mod-pppol2tp + resolveip.
#
# luci-proto-ppp ships htdocs/luci-static/resources/protocol/l2tp.js
# (verified on the openwrt-23.05 / 24.10 / 25.12 luci branches). Without it
# the Interfaces page shows "Unsupported protocol type / Install protocol
# extensions" even though netifd can handle the interface fine.
#
# kmod-l2tp + ppp-mod-pppol2tp (-> kmod-pppol2tp, which depends on kmod-l2tp)
# are the kernel side of the PPP-over-L2TP tunnel.
install_prereqs() {
    MISSING=""
    for p in xl2tpd kmod-l2tp ppp-mod-pppol2tp luci-proto-ppp; do
        pkg_installed "$p" || MISSING="$MISSING $p"
    done
    [ -z "$MISSING" ] && return 0

    $PKG_UPDATE >/dev/null 2>&1

    # One package at a time: apk aborts the WHOLE transaction when a single
    # name is unknown, so a batch would drop everything on one missing name.
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
        echo "       xl2tpd lives in the 'packages' feed, luci-proto-ppp in the"
        echo "       'luci' feed. Enable them and re-run. Without xl2tpd there"
        echo "       is no /lib/netifd/proto/l2tp.sh and no /etc/init.d/xl2tpd."
        return 1
    fi
    return 0
}

install_prereqs
report_status $? "Prerequisites Check/Install (L2TP)"

# --- 3b. Make netifd actually know the l2tp protocol ---
# netifd scans /lib/netifd/proto/ ONCE, at startup. xl2tpd drops
# proto/l2tp.sh there, so if that package was installed after netifd
# booted, the handler is on disk but never registered. `network reload`
# does NOT rescan it — only a restart does. Symptoms when missing:
# LuCI Interfaces shows "Unsupported protocol type / Install protocol
# extensions" even though luci-proto-ppp is installed.
#
# NOTE: only CALLED at the very end of the installer — restarting netifd
# mid-config would bring it up before our UCI changes are committed.
netifd_has_l2tp() {
    ubus call network get_proto_handlers 2>/dev/null | grep -q '"l2tp"'
}

ensure_netifd_proto() {
    netifd_has_l2tp && return 0

    echo " [INFO] netifd has not loaded the l2tp protocol handler yet."

    # Detached on purpose: restarting network drops every interface,
    # which usually kills the very SSH session running this installer.
    # setsid + nohup + the parent exiting lets the restart finish anyway,
    # and the follow-up reload re-reads our committed config.
    ( setsid nohup sh -c '
        /etc/init.d/network restart >/dev/null 2>&1
        sleep 8
        /etc/init.d/network reload  >/dev/null 2>&1
      ' >/dev/null 2>&1 & ) 2>/dev/null

    echo " [WARN] Network is restarting to pick up the l2tp handler."
    echo "        Your SSH/browser session may drop for a few seconds."
    echo "        Re-open LuCI -> Network -> Interfaces afterwards."
    return 0
}

# --- 4. Network Configuration ---
configure_network() {
    uci delete network.$L2TP_IFACE_NAME >/dev/null 2>&1

    uci set network.$L2TP_IFACE_NAME=interface
    uci set network.$L2TP_IFACE_NAME.proto='l2tp'
    uci set network.$L2TP_IFACE_NAME.server="$L2TP_SERVER"
    uci set network.$L2TP_IFACE_NAME.username="$L2TP_USER"
    uci set network.$L2TP_IFACE_NAME.password="$L2TP_PASS"
    uci set network.$L2TP_IFACE_NAME.metric="$METRIC"

    # proto/l2tp.sh builds the pppd options: ipv6=0 leaves out "+ipv6",
    # so no IPv6 is negotiated on the PPP link (no IPv6 leak).
    uci set network.$L2TP_IFACE_NAME.ipv6='0'

    # Critical: do not hijack all traffic. defaultroute/peerdns/metric are
    # netifd's PROTO_DEFAULT_OPTIONS, i.e. valid for every protocol.
    uci set network.$L2TP_IFACE_NAME.defaultroute='0'
    uci set network.$L2TP_IFACE_NAME.peerdns='0'

    # Keepalive "failures interval": becomes
    #   lcp-echo-failure 10 / lcp-echo-interval 60 inside pppd.
    uci set network.$L2TP_IFACE_NAME.keepalive='10 60'

    uci commit network
}

configure_network >/dev/null 2>&1
report_status $? "Network Configuration"

# --- 5. Firewall Configuration ---
configure_firewall() {
    CHANGED=0

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
        CHANGED=1
    fi

    # Checked separately: a half-finished earlier run must be repairable
    if ! uci show firewall | grep -q "dest='$L2TP_ZONE_NAME'"; then
        FWD_KEY=$(uci add firewall forwarding)
        if [ -z "$FWD_KEY" ]; then return 1; fi

        uci set firewall.$FWD_KEY.src='lan'
        uci set firewall.$FWD_KEY.dest="$L2TP_ZONE_NAME"
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
        NODE="l2tp_native_node"
        uci delete $CFG.$NODE >/dev/null 2>&1
        uci set $CFG.$NODE=nodes
        uci set $CFG.$NODE.remarks="$NODE_LABEL"
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

# --- 7. Make sure the xl2tpd daemon survives a reboot ---
# proto/l2tp.sh starts it itself when the interface comes up, but only while
# netifd is bringing the tunnel up. Enable it so a boot with a slow network
# still has /var/run/xl2tpd/l2tp-control available, and start it now if the
# control socket is missing (fresh install of the package).
ensure_xl2tpd() {
    if [ ! -x /etc/init.d/xl2tpd ]; then
        echo "ERROR: /etc/init.d/xl2tpd is missing."
        echo "       xl2tpd did not install; the tunnel cannot be created."
        return 1
    fi

    /etc/init.d/xl2tpd enable >/dev/null 2>&1
    if [ ! -p /var/run/xl2tpd/l2tp-control ]; then
        /etc/init.d/xl2tpd start >/dev/null 2>&1
    fi
    return 0
}

# not redirected: the only thing this prints is the diagnostic on failure
ensure_xl2tpd
report_status $? "xl2tpd Service"

# --- 8. LuCI Shortcut (menu.d JSON + JS view — identical on 23.05/24.10/25.12) ---
MENU_D="/usr/share/luci/menu.d/luci-app-l2tp-shortcut.json"
VIEW_DIR="/www/luci-static/resources/view/l2tp"
LEGACY_LUA="/usr/lib/lua/luci/controller/l2tp_shortcut.lua"

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
	"admin/vpn/l2tp_native": {
		"title": "L2TP Config",
		"order": 30,
		"action": { "type": "view", "path": "l2tp/main" }
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
	"admin/vpn/l2tp_native": {
		"title": "L2TP Config",
		"order": 30,
		"action": { "type": "view", "path": "l2tp/main" }
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
    echo " [OK] Menu Shortcut Created (VPN -> L2TP Config)"
else
    echo " [INFO] LuCI not found, shortcut skipped."
fi

# --- 9. Reload Services ---
# reload, not restart: a restart drops every interface (and the admin's
# remote session) while netifd/fw reload pick up the new config in place.
# The ONE exception is ensure_netifd_proto() below, which must restart
# because netifd never rescans /lib/netifd/proto/ on a reload.
reload_services() {
    /etc/init.d/network reload >/dev/null 2>&1
    /etc/init.d/firewall reload >/dev/null 2>&1
}

if netifd_has_l2tp; then
    reload_services
    report_status $? "Service Reload"
else
    # skip the plain reload — ensure_netifd_proto() is about to restart
    # netifd anyway, and a reload racing that restart would just be noise
    ensure_netifd_proto
    report_status 0 "Service Reload (netifd restart dispatched)"
fi

printf '\nLuCI menu: VPN -> L2TP Config\n'
printf 'Test API:  ifconfig l2tp-%s\n' "$L2TP_IFACE_NAME"
