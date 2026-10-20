#!/bin/sh

# ==========================================
# OpenWrt Native IKEv2 Setup + Passwall + UI Shortcut
# (Silent Mode - Tun Device Fix & Bulletproof Restart)
#
# Works on OpenWrt 23.05 / 24.10 (opkg) and 25.12+ (apk).
#
# NOTE: unlike WireGuard-Plus / SStp-Plus, this app has NO netifd protocol
# handler. The interface is proto='none' bound to the ipsec0 device that
# strongswan's kernel-libipsec plugin creates, so there is nothing for
# netifd to scan and no luci-proto-* package to install — LuCI always
# registers the 'none' protocol itself.
# ==========================================

printf '\n--- IKEv2-Plus By PeDitX ---\n\n'

# --- 1. USER CONFIGURATION (EDIT THIS) ---
IKEV2_SERVER="vpn.example.com"
IKEV2_USER="my_username"
IKEV2_PASS="my_password"

# Naming Constants
IKEV2_DEV_NAME="ipsec0"   # Created by kernel-libipsec
IKEV2_IFACE_NAME="ikev2_plus"
IKEV2_ZONE_NAME="ikev2_zone"
NODE_LABEL="IKEv2-Native-Direct"

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
# write an empty path into menu.d.
render() {
    if [ -z "$IKEV2_IFACE_NAME" ]; then
        echo "ERROR: render: IKEV2_IFACE_NAME is empty"
        exit 1
    fi
    sed -e "s|@IFACE@|${IKEV2_IFACE_NAME}|g" > "$1"
    if grep -q '@IFACE@' "$1"; then
        echo "ERROR: render: unsubstituted marker left in $1"
        exit 1
    fi
}

# --- 3. Prerequisites (install ONLY what is missing) ---
# Never re-install luci-base on a device that has it — a custom firmware's
# copy is load-bearing for the theme and every other app.
#
# strongswan-ipsec is NOT optional, and strongswan-default does NOT pull it
# in (verified against openwrt/packages 25.12 Makefile): it is the ONLY
# package that ships /etc/init.d/ipsec and /usr/sbin/ipsec. Without it the
# service management further down has nothing to talk to.
#
# kmod-tun is left installed on purpose by the uninstaller — the TUN device
# is shared infrastructure (OpenVPN and others use it), not ours to remove.
install_prereqs() {
    MISSING=""
    for p in strongswan-default strongswan-ipsec \
             strongswan-mod-eap-mschapv2 strongswan-mod-eap-identity \
             strongswan-mod-kernel-libipsec kmod-tun; do
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
        echo "       Check that the 'packages' feed is enabled and re-run."
        echo "       Without strongswan-ipsec there is no /etc/init.d/ipsec."
        return 1
    fi
    return 0
}

install_prereqs
report_status $? "Prerequisites Check/Install (IKEv2)"

# --- 4. Ensure TUN Device is Available (CRITICAL FIX) ---
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

# --- 5. Configure StrongSwan (ipsec.conf) ---
configure_ipsec() {
    mkdir -p /etc/ipsec.d

    # Backup existing config SAFELY
    if [ -f /etc/ipsec.conf ] && [ ! -f /etc/ipsec.conf.bak ]; then
        cp /etc/ipsec.conf /etc/ipsec.conf.bak
    fi

    if [ -f /etc/ipsec.secrets ] && [ ! -f /etc/ipsec.secrets.bak ]; then
        cp /etc/ipsec.secrets /etc/ipsec.secrets.bak
    fi

    # NOTE: unquoted EOF on purpose — $IKEV2_SERVER / $IKEV2_USER must expand.
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

# --- 6. Network Configuration ---
configure_network() {
    uci delete network.$IKEV2_IFACE_NAME >/dev/null 2>&1

    uci set network.$IKEV2_IFACE_NAME=interface
    # 'none' is built into LuCI's protocol set, so no luci-proto package and
    # no netifd proto script are involved — see the header note.
    uci set network.$IKEV2_IFACE_NAME.proto='none'
    uci set network.$IKEV2_IFACE_NAME.device="$IKEV2_DEV_NAME"

    uci commit network
}

configure_network >/dev/null 2>&1
report_status $? "Network Configuration"

# --- 7. Firewall Configuration ---
configure_firewall() {
    CHANGED=0

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
        CHANGED=1
    fi

    # Checked separately: a half-finished earlier run must be repairable
    if ! uci show firewall | grep -q "dest='$IKEV2_ZONE_NAME'"; then
        FWD_KEY=$(uci add firewall forwarding)
        if [ -z "$FWD_KEY" ]; then return 1; fi

        uci set firewall.$FWD_KEY.src='lan'
        uci set firewall.$FWD_KEY.dest="$IKEV2_ZONE_NAME"
        CHANGED=1
    fi

    [ "$CHANGED" -eq 1 ] && uci commit firewall
    return 0
}

configure_firewall >/dev/null 2>&1
report_status $? "Firewall Configuration"

# --- 8. Passwall Configuration ---
configure_passwall() {
    FOUND=0

    add_node() {
        CFG=$1
        NODE="ikev2_native_node"
        uci delete $CFG.$NODE >/dev/null 2>&1
        uci set $CFG.$NODE=nodes
        uci set $CFG.$NODE.remarks="$NODE_LABEL"
        # bound to the ipsec0 DEVICE, not the logical ikev2_plus interface
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

# --- 9. LuCI Shortcut (menu.d JSON + JS view — identical on 23.05/24.10/25.12) ---
MENU_D="/usr/share/luci/menu.d/luci-app-ikev2-shortcut.json"
VIEW_DIR="/www/luci-static/resources/view/ikev2"
LEGACY_LUA="/usr/lib/lua/luci/controller/ikev2_shortcut.lua"

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
	"admin/vpn/ikev2_native": {
		"title": "IKEv2 Status",
		"order": 40,
		"action": { "type": "view", "path": "ikev2/main" }
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
	"admin/vpn/ikev2_native": {
		"title": "IKEv2 Status",
		"order": 40,
		"action": { "type": "view", "path": "ikev2/main" }
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
    echo " [OK] Menu Shortcut Created (VPN -> IKEv2 Status)"
else
    echo " [INFO] LuCI not found, shortcut skipped."
fi

# --- 10. Restart Services (WITH TUN CHECK) ---
# network/fw use reload (not restart) so a remote admin's session survives.
# The ipsec side is deliberately a HARD restart: charon caches its config at
# startup and will not pick up a rewritten /etc/ipsec.conf otherwise.
restart_services() {
    # 1. Ensure TUN is ready (Just in case)
    check_tun_device >/dev/null 2>&1

    # 2. Network + Firewall reload (safe)
    /etc/init.d/network reload >/dev/null 2>&1
    sleep 3
    /etc/init.d/firewall reload >/dev/null 2>&1

    # 3. IPsec Clean Restart — requires strongswan-ipsec for this script
    if [ ! -x /etc/init.d/ipsec ]; then
        echo "ERROR: /etc/init.d/ipsec is missing."
        echo "       strongswan-ipsec did not install; charon cannot start."
        return 1
    fi
    /etc/init.d/ipsec enable >/dev/null 2>&1

    # Force stop & kill stuck processes
    /etc/init.d/ipsec stop >/dev/null 2>&1
    killall -9 charon >/dev/null 2>&1
    sleep 2

    # Start fresh
    /etc/init.d/ipsec start >/dev/null 2>&1

    # 4. Verify
    sleep 2
    if pgrep charon >/dev/null; then
        return 0
    fi
    # Fallback
    /etc/init.d/ipsec restart >/dev/null 2>&1
    sleep 2
    if pgrep charon >/dev/null; then
        return 0
    fi
    return 1
}

restart_services
report_status $? "Service Restart"
