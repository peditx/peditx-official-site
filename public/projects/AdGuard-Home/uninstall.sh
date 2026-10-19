#!/bin/sh
# ============================================================
#  AdGuard Home — PeDitXOS standalone uninstaller
#  Removes only the paths this installer created. Never globs.
# ============================================================

APP_NAME="adguardhome"
APP_TITLE="AdGuard Home"

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

PKG_INSTALLED() {
	if [ "$PKG" = "apk" ]; then
		apk info -e "$1" >/dev/null 2>&1
	elif [ "$PKG" = "opkg" ]; then
		opkg status "$1" 2>/dev/null | grep -q '^Status:.*installed'
	else
		return 1
	fi
}

echo
echo ">>> Removing ${APP_TITLE}..."

# --- Service ------------------------------------------------------
if [ -f /etc/init.d/adguardhome ]; then
	/etc/init.d/adguardhome stop >/dev/null 2>&1
	/etc/init.d/adguardhome disable >/dev/null 2>&1
	echo "   - Service stopped."
fi

# --- Package -------------------------------------------------------
if [ -n "$PKG_REMOVE" ] && PKG_INSTALLED adguardhome; then
	$PKG_REMOVE adguardhome >/dev/null 2>&1
	echo "   - Package removed."
fi

# --- Dnsmasq back to port 53 + ISP DNS ------------------------------
uci -q set dhcp.@dnsmasq[0].port='53'
uci -q delete dhcp.@dnsmasq[0].noresolv
uci -q commit dhcp
/etc/init.d/dnsmasq restart >/dev/null 2>&1
echo "   - dnsmasq restored (port 53, ISP DNS)."

# --- Firewall -------------------------------------------------------
if uci -q get firewall.AdGuardHomeWeb >/dev/null 2>&1; then
	uci -q delete firewall.AdGuardHomeWeb
	uci -q commit firewall
	/etc/init.d/firewall restart >/dev/null 2>&1
	echo "   - Firewall rule removed."
fi

# --- Config ----------------------------------------------------------
rm -f /etc/adguardhome.yaml
echo "   - Configuration removed."

# --- LuCI files owned by this installer ------------------------
rm -f  "/usr/share/luci/menu.d/luci-app-${APP_NAME}.json"
rm -f  "/usr/share/rpcd/acl.d/luci-app-${APP_NAME}.json"
rm -rf "/www/luci-static/resources/view/${APP_NAME}"
rm -f  "/usr/bin/${APP_NAME}-backend.sh"
echo "   - LuCI page removed."

# --- files left by the previous (Lua) version -------------------
# (no Lua files from a previous version)

# --- rpcd re-reads acl.d; ucode LuCI caches ---------------------
/etc/init.d/rpcd reload >/dev/null 2>&1
rm -f /tmp/luci-indexcache /tmp/luci-sessions/.root 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null

echo "Note: DNS settings were restored to the stock dnsmasq state."

echo ">>> ${APP_TITLE} removed. Refresh your browser (and log out/in if the menu lingers)."
echo "------------------------------------------"
